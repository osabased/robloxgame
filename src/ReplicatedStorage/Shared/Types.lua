--!strict
-- ReplicatedStorage/Shared/Types.luau

export type IPlayerService = {
	init: () -> (),
	start: () -> (),
	GetPlayer: (userId: number) -> Player?
}

export type IUIController = {
	init: () -> (),
	start: () -> (),
	ShowHUD: () -> ()
}

export type ITableUtils = {
	DeepCopy: <T>(t: T) -> T,
	Keys: (t: {[any]: any}) -> {any}
}

export type IStateDefinition = {
	animationId: string,
	fadeTime: number,
	looped: boolean,
	priority: Enum.AnimationPriority,
	guard: ((currentState: string?) -> boolean)?,
	-- NOTE: guard functions must never yield or error.
	-- They are called synchronously inside TransitionTo() and _transitionApproved().
	isAction: boolean,
	-- true  = server-validated; callers must use RequestActionState().
	-- false = client-authoritative; callers use TransitionTo() directly.
}

export type IAnimationController = {
	init: () -> (),
	start: () -> (),
	WaitUntilReady: () -> (),
	-- outgoingFadeTime: fadeTime of the state being exited; governs the stop blend.
	-- definition.fadeTime: fadeTime of the state being entered; governs the play blend.
	Play: (stateName: string, definition: IStateDefinition, outgoingFadeTime: number?) -> boolean,
	Stop: (fadeTime: number?) -> (),
	GetCurrentStateName: () -> string?
}

export type IStateMachineController = {
	init: () -> (),
	start: () -> (),
	Setup: (states: {[string]: IStateDefinition}, runThreshold: number) -> (),
	RegisterState: (name: string, definition: IStateDefinition) -> (),
	TransitionTo: (stateName: string) -> boolean,
	GetCurrentState: () -> string?,
	RequestActionState: (stateName: string) -> (),
	-- Returns nil if no server-approved action state has been broadcast for
	-- this player. Locomotion states (Idle, Walk, Run, etc.) are
	-- client-authoritative and are never tracked here.
	GetRemotePlayerState: (player: Player) -> string?
}

export type IAnimationService = {
	init: () -> (),
	start: () -> (),
	RegisterActionState: (name: string) -> (),
	SetPlayerCondition: (player: Player, condition: string, value: boolean) -> ()
}

return {} -- Returning {} instead of the type definitions prevents circular dependencies; types are compile-time constructs only and have no runtime representation.
