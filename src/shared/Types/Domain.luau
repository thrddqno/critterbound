--!strict

-- Static definitions: authored game data shared by every instance.

export type CritterClass = "Verdant" | "Tide" | "Feral" | "Gale" | "Shade" | "Stone"

export type TargetingRule =
	"SELF"
	| "ALLY"
	| "ENEMY"
	| "ANY"
	| "FRONT_ENEMY"
	| "ALL_ALLIES"
	| "ALL_ENEMIES"

export type CritterStats = {
	maxHealth: number,
	attack: number,
	defense: number,
	speed: number,
	skill: number?,
	resolve: number?,
}

export type CritterDefinition = {
	schemaVersion: number,
	id: string,
	displayName: string,
	class: CritterClass,
	baseStats: CritterStats,
	abilityIds: { string },
}

export type CardEffectKind = "DAMAGE" | "HEAL" | "SHIELD" | "STATUS"

-- Effects execute in authored array order. Only the fields relevant to `kind` are read.
export type CardEffect = {
	kind: CardEffectKind,
	amount: number?,
	statusId: string?,
	magnitude: number?,
	duration: number?,
}

export type CardDefinition = {
	schemaVersion: number,
	id: string,
	displayName: string,
	class: CritterClass,
	abilityId: string,
	energyCost: number,
	targetingRule: TargetingRule,
	effects: { CardEffect }?,
}

-- Persistent creature data: owned identity and independently inherited genomes.

export type AppearanceGenome = {
	schemaVersion: number,
	speciesId: string,
	bodyVariantId: string,
	paletteId: string,
	patternId: string,
}

export type AbilityGenome = {
	schemaVersion: number,
	abilityIds: { string },
}

export type CritterInstance = {
	schemaVersion: number,
	id: string,
	definitionId: string,
	ownerUserId: number,
	appearanceGenome: AppearanceGenome,
	abilityGenome: AbilityGenome,
}

export type CardInstance = {
	id: string,
	definitionId: string,
	sourceCritterInstanceId: string,
}

-- Temporary battle state: never persisted as creature ownership data.

export type BattlePhase =
	"CREATED"
	| "ROUND_START"
	| "PLANNING"
	| "COMMITTED"
	| "RESOLVING"
	| "ROUND_END"
	| "COMPLETED"

export type StatusEffect = {
	id: string,
	statusId: string,
	sourceCombatantId: string,
	targetCombatantId: string,
	magnitude: number,
	duration: number,
	stackCount: number,
	appliedRound: number,
	expiresAtRound: number,
}

export type BattleShield = {
	id: string,
	sourceCombatantId: string,
	amount: number,
	expiresAtRound: number,
}

export type BattleCombatant = {
	id: string,
	critterInstanceId: string,
	teamId: string,
	slot: number,
	class: CritterClass,
	abilityIds: { string },
	stats: CritterStats,
	currentHealth: number,
	statusEffects: { StatusEffect },
	shields: { BattleShield }?,
}

export type BattleTeam = {
	id: string,
	ownerUserId: number,
	teamIndex: number?,
	combatantIds: { string },
}

export type QueuedCard = {
	cardInstanceId: string,
	sourceCombatantId: string,
	targetCombatantIds: { string },
	queueIndex: number,
}

export type BattleCommandType =
	"QUEUE_CARD"
	| "REMOVE_QUEUED_CARD"
	| "REORDER_QUEUED_CARD"
	| "CLEAR_PLAN"
	| "COMMIT_PLAN"

export type BattleCommandEnvelope = {
	protocolVersion: number,
	matchId: string,
	teamId: string,
	commandId: string,
	expectedStateVersion: number,
	expectedPlanVersion: number,
	commandType: BattleCommandType,
	payload: { [string]: any },
}

export type BattleCommand = BattleCommandEnvelope

export type RngState = {
	algorithm: "PARK_MILLER_V1",
	state: number,
	drawCount: number,
}

export type TeamRoundState = {
	teamId: string,
	energy: number,
	reservedEnergy: number?,
	drawPileCardInstanceIds: { string }?,
	handCardInstanceIds: { string },
	discardCardInstanceIds: { string }?,
	queuedCards: { QueuedCard }?,
	planVersion: number?,
	committed: boolean,
}

export type BattleState = {
	schemaVersion: number,
	id: string,
	rngSeed: number,
	rng: RngState?,
	stateVersion: number?,
	eventVersion: number?,
	lastResolvedRound: number?,
	phase: BattlePhase,
	roundNumber: number,
	teams: { BattleTeam },
	combatants: { BattleCombatant },
	cardInstances: { CardInstance }?,
	teamRoundStates: { TeamRoundState },
}

export type BattleEvent = {
	id: string,
	battleId: string,
	sequence: number,
	roundNumber: number,
	kind: string,
	sourceCombatantId: string?,
	targetCombatantIds: { string },
	payload: { [string]: any }?,
}

export type BattleOutcome = {
	isDraw: boolean,
	winnerTeamId: string?,
	reason: string,
}

export type BattleResolutionResult = {
	state: BattleState,
	events: { BattleEvent },
	stateVersion: number,
	matchOutcome: BattleOutcome?,
}

export type InitiativeEntry = {
	combatantId: string,
	teamIndex: number,
	slot: number,
	speed: number,
	queuedCards: { QueuedCard },
}

-- Shared success/error convention.

export type DomainError = {
	code: string,
	message: string,
	path: string?,
}

export type DomainSuccess<T> = {
	ok: true,
	value: T,
}

export type DomainFailure = {
	ok: false,
	errors: { DomainError },
}

export type DomainResult<T> = DomainSuccess<T> | DomainFailure

-- Deferred persistence types retained for Run 1 compatibility.

export type ItemRecord = {
	id: string,
	schemaVersion: number,
}

export type PlayerProfile = {
	userId: number,
	schemaVersion: number,
}

export type TradeRecord = {
	id: string,
	schemaVersion: number,
}

return table.freeze({})
