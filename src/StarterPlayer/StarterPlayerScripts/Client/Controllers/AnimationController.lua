--!strict
-- StarterPlayerScripts/Client/Controllers/AnimationController.luau

local DEFAULT_FADE_TIME: number = 0.1 -- Default blend duration used when no fadeTime is provided by the caller or outgoing state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

-- GoodSignal is required at root level: it is a standalone library with no SSA
-- dependencies. It replaces _readyBindable (a BindableEvent) with a pure-Lua signal —
-- no Instance allocation, no replication overhead, and no manual :Destroy() required.
local GoodSignal = require(ReplicatedStorage.Packages.goodsignal)

local IAnimationController = {}
local _animator: Animator?
local _currentTrack: AnimationTrack?
local _currentStateName: string?
local _trackCache: { [string]: AnimationTrack } = {}
local _ready: boolean = false
-- _readySignal is always non-nil after init(). Each character lifetime gets a fresh
-- signal; the previous one is fired once (to wake any stale WaitUntilReady callers)
-- before being replaced, matching the prior BindableEvent :Destroy() semantics.
local _readySignal = GoodSignal.new()
local _respawnToken: number = 0

function IAnimationController.init()
	-- Fire the current signal before replacing it so any callers blocked in
	-- WaitUntilReady() from a previous session (e.g. test harness) are resumed
	-- rather than left hanging forever.
	_readySignal:Fire()
	_readySignal = GoodSignal.new()
	_trackCache = {}
	_ready = false
	_respawnToken = 0
end

function IAnimationController.start()
	local function signalReady()
		_ready = true
		-- Fire releases any coroutines currently blocked in WaitUntilReady:Wait().
		-- No cleanup needed — GoodSignal is GC'd normally; unlike BindableEvent it
		-- is not a Roblox Instance and carries no replication or leak risk.
		_readySignal:Fire()
	end

	local function acquireAnimator(character: Model, token: number): boolean
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		if token ~= _respawnToken then
			return false
		end
		local animator = humanoid:WaitForChild("Animator") :: Animator
		if token ~= _respawnToken then
			return false
		end
		_animator = animator
		return true
	end

	local localPlayer = Players.LocalPlayer

	localPlayer.CharacterAdded:Connect(function(newCharacter)
		_respawnToken += 1
		local token = _respawnToken

		_ready = false
		local track = _currentTrack
		if track and track.IsPlaying then
			track:Stop(0)
		end
		_currentTrack = nil
		_currentStateName = nil
		_trackCache = {}

		-- Fire the current signal before replacing it to resume any coroutine that is
		-- blocked inside WaitUntilReady():Wait() for the *previous* character. The caller
		-- (StateMachineController) uses a _setupToken guard to discard stale resumes, so
		-- waking them here is safe. This matches the behaviour of the previous code, which
		-- relied on BindableEvent:Destroy() to implicitly resume pending :Wait() calls.
		_readySignal:Fire()
		_readySignal = GoodSignal.new()

		if not acquireAnimator(newCharacter, token) then
			return
		end

		signalReady()
	end)

	if localPlayer.Character then
		_respawnToken += 1
		local token = _respawnToken
		if acquireAnimator(localPlayer.Character, token) then
			signalReady()
		end
	else
		local character = localPlayer.CharacterAdded:Wait()
		_respawnToken += 1
		local token = _respawnToken
		if acquireAnimator(character, token) then
			signalReady()
		end
	end
end

function IAnimationController.WaitUntilReady()
	if _ready then
		return
	end
	-- _readySignal is always set after init(). If it is somehow nil, the caller
	-- invoked WaitUntilReady before SSA Phase 2 ran.
	if not _readySignal then
		error("AnimationController: WaitUntilReady called before init() — ensure SSA Phase 2 has run")
	end
	_readySignal:Wait()
end

function IAnimationController.Play(
	stateName: string,
	definition: Types.IStateDefinition,
	outgoingFadeTime: number?
): boolean
	if not _ready then
		warn("AnimationController: Play called before Animator is ready")
		return false
	end
	if stateName == _currentStateName then
		return true
	end

	local outgoingTrack = _currentTrack
	if outgoingTrack and outgoingTrack.IsPlaying then
		outgoingTrack:Stop(outgoingFadeTime or DEFAULT_FADE_TIME)
		-- The outgoing state's fadeTime controls the exit blend. The incoming state's
		-- definition.fadeTime controls the enter blend. Both are in play; each state
		-- owns its own blend boundary.
	end

	local track = _trackCache[stateName]
	if track and track.Animation and track.Animation.AnimationId == definition.animationId then
		-- Reuse cached track.
	else
		if not _animator then
			warn("AnimationController: _animator is nil despite _ready being true — possible acquire failure")
			_ready = false
			return false
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = definition.animationId
		local existing = _trackCache[stateName]
		if existing then
			existing:Destroy()
		end
		track = _animator:LoadAnimation(animation)
		_trackCache[stateName] = track
	end

	-- Priority MUST be set before calling Play() or it has no effect on an already-loaded track.
	track.Priority = definition.priority
	track.Looped = definition.looped
	track:Play(definition.fadeTime)

	_currentTrack = track
	_currentStateName = stateName

	return true
end

function IAnimationController.Stop(fadeTime: number?)
	local track = _currentTrack
	if track and track.IsPlaying then
		track:Stop(fadeTime or DEFAULT_FADE_TIME)
	end
	_currentTrack = nil
	_currentStateName = nil
end

function IAnimationController.GetCurrentStateName(): string?
	return _currentStateName
end

return IAnimationController
