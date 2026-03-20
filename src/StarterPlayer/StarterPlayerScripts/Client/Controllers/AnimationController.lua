--!strict
local DEFAULT_FADE_TIME: number = 0.1

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local IAnimationController = {}
local _animator: Animator?
local _currentTrack: AnimationTrack?
local _currentStateName: string?
local _trackCache: { [string]: AnimationTrack } = {}
local _ready: boolean = false
local _readyBindable: BindableEvent?
local _respawnToken: number = 0

function IAnimationController.init()
	_readyBindable = Instance.new("BindableEvent")
	_trackCache = {}
	_ready = false
	_respawnToken = 0
end

function IAnimationController.start()
	local function signalReady()
		_ready = true
		if _readyBindable then
			_readyBindable:Fire()
			_readyBindable:Destroy()
			_readyBindable = nil
		end
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
		if _readyBindable then
			_readyBindable:Destroy()
		end
		_readyBindable = Instance.new("BindableEvent")

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
	if _readyBindable then
		_readyBindable.Event:Wait()
	else
		error("AnimationController: WaitUntilReady called before init()")
	end
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
	end

	local track = _trackCache[stateName]
	if track and track.Animation and track.Animation.AnimationId == definition.animationId then
		-- reuse cached track
	else
		if not _animator then
			warn("AnimationController: _animator is nil despite _ready being true")
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

	-- Priority must be set before Play() or it has no effect on an already-loaded track.
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
