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
	guard: ((currentState: string?) -> boolean)?,
	isAction: boolean,
}

export type IAnimationController = {
	init: () -> (),
	start: () -> (),
	WaitUntilReady: () -> (),
	Play: (stateName: string, definition: IStateDefinition, outgoingFadeTime: number?) -> boolean,
	Stop: (fadeTime: number?) -> (),
	GetCurrentStateName: () -> string?,
}

export type IStateMachineController = {
	init: () -> (),
	start: () -> (),
	-- Merges a batch of states into the registry. Safe to call multiple times during init.
	RegisterStates: (states: { [string]: IStateDefinition }) -> (),
	-- Called once by whichever module owns the locomotion threshold.
	SetRunThreshold: (threshold: number) -> (),
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

return {}
