--!strict
-- Canonical state name constants. Use everywhere a state name appears as a string:
-- guards, TransitionTo, RequestActionState, and state table keys.
return table.freeze({
	Idle  = "Idle",
	Walk  = "Walk",
	Run   = "Run",
	Jump  = "Jump",
	Fall  = "Fall",
	Swim  = "Swim",
	Climb = "Climb",
	Emote = "Emote",
	Stun  = "Stun",
})
