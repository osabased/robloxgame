--!strict
export type IPlayerService = {
	init: () -> (),
	start: () -> (),
	GetPlayer: (userId: number) -> Player?,
}

export type IUIController = {
	init: () -> (),
	start: () -> (),
	ShowHUD: () -> (),
}

export type ITableUtils = {
	DeepCopy: <T>(t: T) -> T,
	Keys: (t: { [any]: any }) -> { any },
}

export type IStateDefinition = {
	animationId: string,
	fadeTime: number,
	looped: boolean,
	priority: Enum.AnimationPriority,
	-- guard must never yield or error; called synchronously inside TransitionTo().
	guard: ((currentState: string?) -> boolean)?,
	-- true  = server-validated; use RequestActionState().
	-- false = client-authoritative; use TransitionTo() directly.
	isAction: boolean,
}

export type IAnimationController = {
	init: () -> (),
	start: () -> (),
	WaitUntilReady: () -> (),
	-- outgoingFadeTime: governs the stop blend of the exiting state.
	-- definition.fadeTime: governs the play blend of the entering state.
	Play: (stateName: string, definition: IStateDefinition, outgoingFadeTime: number?) -> boolean,
	Stop: (fadeTime: number?) -> (),
	GetCurrentStateName: () -> string?,
}

export type IStateMachineController = {
	init: () -> (),
	start: () -> (),
	Setup: (states: { [string]: IStateDefinition }, runThreshold: number) -> (),
	RegisterState: (name: string, definition: IStateDefinition) -> (),
	TransitionTo: (stateName: string) -> boolean,
	GetCurrentState: () -> string?,
	RequestActionState: (stateName: string) -> (),
	GetRemotePlayerState: (player: Player) -> string?,
	Destroy: () -> (),
}

export type IAnimationService = {
	init: () -> (),
	start: () -> (),
	RegisterActionState: (name: string) -> (),
	SetPlayerCondition: (player: Player, condition: string, value: boolean) -> (),
}

-- Returning {} instead of type definitions prevents circular dependencies;
-- types are compile-time constructs with no runtime representation.
return {}
