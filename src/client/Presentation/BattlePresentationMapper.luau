--!strict

export type PresentationError = { code: string, message: string, path: string? }
export type CritterModel = {
	id: string,
	critterInstanceId: string,
	teamId: string,
	slot: number,
	class: string,
	displayName: string,
	assetId: string,
	appearanceGenome: any,
	health: number,
	maxHealth: number,
	shield: number,
	speed: number,
	statuses: { any },
	defeated: boolean,
}
export type TeamModel = {
	id: string,
	ownerUserId: number,
	side: "ALLY" | "ENEMY",
	critters: { CritterModel },
}
export type CardModel = {
	id: string,
	definitionId: string,
	displayName: string,
	class: string,
	energyCost: number,
	targetingRule: string,
	description: string,
	sourceCombatantId: string,
	assetId: string,
}
export type InitiativeModel = {
	position: number,
	combatantId: string,
	displayName: string,
	class: string,
	teamId: string,
	side: "ALLY" | "ENEMY",
	speed: number,
}
export type QueueModel = { card: CardModel, sourceOrder: number }
export type EnergyModel = { available: number, allocated: number, remaining: number }
export type BattlePresentationModel = {
	revision: number,
	planVersion: number,
	viewerTeamId: string,
	battleId: string,
	roundNumber: number,
	phase: string,
	teams: { TeamModel },
	critters: { CritterModel },
	hand: { CardModel },
	visibleQueue: { QueueModel },
	initiative: { InitiativeModel },
	energy: EnergyModel,
	canPlan: boolean,
	canRequestCommit: boolean,
	matchOutcome: any?,
}
export type AuthoritativePresentationSnapshot = {
	revision: number,
	viewerTeamId: string,
	battleState: any,
	critterInstancesById: { [string]: any },
	critterDefinitionsById: { [string]: any },
	cardInstancesById: { [string]: any },
	cardDefinitionsById: { [string]: any },
	shieldsByCombatantId: { [string]: number },
	effectiveSpeedByCombatantId: { [string]: number }?,
	initiativeCombatantIds: { string },
	visibleQueuedCards: { any },
	matchOutcome: any?,
}
export type PresentationResult =
	{ ok: true, value: BattlePresentationModel }
	| { ok: false, errors: { PresentationError } }

local function addError(errors: { PresentationError }, code: string, message: string, path: string?)
	table.insert(errors, { code = code, message = message, path = path })
end

local function indexById(
	values: { any },
	errors: { PresentationError },
	path: string
): { [string]: any }
	local result = {}
	for index, value in values do
		if type(value) ~= "table" or type(value.id) ~= "string" then
			addError(errors, "INVALID_RECORD", "Expected record with string id", `{path}[{index}]`)
		elseif result[value.id] ~= nil then
			addError(errors, "DUPLICATE_ID", "Identifiers must be unique", `{path}[{index}].id`)
		else
			result[value.id] = value
		end
	end
	return result
end

local function map(snapshot: any): PresentationResult
	local errors: { PresentationError } = {}
	if type(snapshot) ~= "table" or type(snapshot.battleState) ~= "table" then
		return {
			ok = false,
			errors = { { code = "INVALID_SNAPSHOT", message = "Expected battle snapshot" } },
		}
	end

	local battle = snapshot.battleState
	if type(battle.teams) ~= "table" or #battle.teams ~= 2 then
		addError(
			errors,
			"INVALID_TEAM_COUNT",
			"BattleScreen requires exactly two teams",
			"battleState.teams"
		)
	end
	local combatants = indexById(battle.combatants or {}, errors, "battleState.combatants")
	local critterInstances = snapshot.critterInstancesById or {}
	local critterDefinitions = snapshot.critterDefinitionsById or {}
	local cardInstances = snapshot.cardInstancesById or {}
	local cardDefinitions = snapshot.cardDefinitionsById or {}

	local orderedTeams = {}
	for _, team in battle.teams or {} do
		table.insert(orderedTeams, team)
	end
	table.sort(orderedTeams, function(a, b)
		if a.id == snapshot.viewerTeamId then
			return true
		end
		if b.id == snapshot.viewerTeamId then
			return false
		end
		return a.id < b.id
	end)

	local teamModels = {}
	local critterModels = {}
	local critterModelsById = {}
	for teamIndex, team in orderedTeams do
		if type(team.combatantIds) ~= "table" or #team.combatantIds ~= 3 then
			addError(
				errors,
				"INVALID_TEAM_SIZE",
				"Each presentation team requires three combatants",
				`battleState.teams[{teamIndex}]`
			)
		end
		local teamCritters = {}
		for _, combatantId in team.combatantIds or {} do
			local combatant = combatants[combatantId]
			if combatant == nil then
				addError(
					errors,
					"MISSING_COMBATANT",
					"Team references missing combatant",
					combatantId
				)
			else
				local instance = critterInstances[combatant.critterInstanceId]
				local definition = instance and critterDefinitions[instance.definitionId]
				if instance == nil or definition == nil then
					addError(
						errors,
						"MISSING_CRITTER_REFERENCE",
						"Combatant creature data is incomplete",
						combatantId
					)
				else
					local model = {
						id = combatant.id,
						critterInstanceId = combatant.critterInstanceId,
						teamId = combatant.teamId,
						slot = combatant.slot,
						class = combatant.class,
						displayName = definition.displayName,
						assetId = `creature.{string.lower(combatant.class)}.default`,
						appearanceGenome = instance.appearanceGenome,
						health = combatant.currentHealth,
						maxHealth = combatant.stats.maxHealth,
						shield = (snapshot.shieldsByCombatantId or {})[combatant.id] or 0,
						speed = (snapshot.effectiveSpeedByCombatantId or {})[combatant.id]
							or combatant.stats.speed,
						statuses = combatant.statusEffects or {},
						defeated = combatant.currentHealth <= 0,
					}
					table.insert(teamCritters, model)
					table.insert(critterModels, model)
					critterModelsById[model.id] = model
				end
			end
		end
		table.sort(teamCritters, function(a, b)
			return a.slot < b.slot
		end)
		table.insert(teamModels, {
			id = team.id,
			ownerUserId = team.ownerUserId,
			side = if team.id == snapshot.viewerTeamId then "ALLY" else "ENEMY",
			critters = teamCritters,
		})
	end

	local roundState = nil
	for _, state in battle.teamRoundStates or {} do
		if state.teamId == snapshot.viewerTeamId then
			roundState = state
			break
		end
	end
	if roundState == nil then
		addError(
			errors,
			"MISSING_TEAM_ROUND_STATE",
			"Viewer team round state is missing",
			"viewerTeamId"
		)
	end

	local hand = {}
	local cardModelsById = {}
	for index, cardInstanceId in (roundState and roundState.handCardInstanceIds) or {} do
		local instance = cardInstances[cardInstanceId]
		local definition = instance and cardDefinitions[instance.definitionId]
		if instance == nil or definition == nil then
			addError(
				errors,
				"MISSING_CARD_REFERENCE",
				"Hand card data is incomplete",
				`hand[{index}]`
			)
		else
			local sourceId = nil
			for _, critter in critterModels do
				if critter.critterInstanceId == instance.sourceCritterInstanceId then
					sourceId = critter.id
					break
				end
			end
			if sourceId == nil then
				addError(
					errors,
					"MISSING_CARD_SOURCE",
					"Hand card source Critter is not present",
					`hand[{index}]`
				)
			else
				local cardModel = {
					id = instance.id,
					definitionId = definition.id,
					displayName = definition.displayName,
					class = definition.class,
					energyCost = definition.energyCost,
					targetingRule = definition.targetingRule,
					description = definition.description or `Target: {definition.targetingRule}`,
					sourceCombatantId = sourceId,
					assetId = definition.id,
				}
				table.insert(hand, cardModel)
				cardModelsById[cardModel.id] = cardModel
			end
		end
	end

	local visibleQueue = {}
	for index, queuedCard in snapshot.visibleQueuedCards or {} do
		local cardModel = cardModelsById[queuedCard.cardInstanceId]
		if cardModel == nil then
			local instance = cardInstances[queuedCard.cardInstanceId]
			local definition = instance and cardDefinitions[instance.definitionId]
			if instance ~= nil and definition ~= nil then
				cardModel = {
					id = instance.id,
					definitionId = definition.id,
					displayName = definition.displayName,
					class = definition.class,
					energyCost = definition.energyCost,
					targetingRule = definition.targetingRule,
					description = definition.description or `Target: {definition.targetingRule}`,
					sourceCombatantId = queuedCard.sourceCombatantId,
					assetId = definition.id,
				}
			else
				addError(
					errors,
					"MISSING_CARD_REFERENCE",
					"Visible queue card data is incomplete",
					`visibleQueuedCards[{index}]`
				)
			end
		end
		if cardModel ~= nil then
			table.insert(visibleQueue, { card = cardModel, sourceOrder = queuedCard.queueIndex })
		end
	end

	local initiative = {}
	for position, combatantId in snapshot.initiativeCombatantIds or {} do
		local critter = critterModelsById[combatantId]
		if critter == nil then
			addError(
				errors,
				"MISSING_INITIATIVE_COMBATANT",
				"Initiative references missing combatant",
				`initiativeCombatantIds[{position}]`
			)
		else
			table.insert(initiative, {
				position = position,
				combatantId = combatantId,
				displayName = critter.displayName,
				class = critter.class,
				teamId = critter.teamId,
				side = if critter.teamId == snapshot.viewerTeamId then "ALLY" else "ENEMY",
				speed = critter.speed,
			})
		end
	end

	if #errors > 0 then
		return { ok = false, errors = errors }
	end

	local energy = roundState.energy
	local allocated = roundState.reservedEnergy or 0
	return {
		ok = true,
		value = {
			revision = snapshot.revision,
			planVersion = snapshot.planVersion or 0,
			viewerTeamId = snapshot.viewerTeamId,
			battleId = battle.id,
			roundNumber = battle.roundNumber,
			phase = battle.phase,
			teams = teamModels,
			critters = critterModels,
			hand = hand,
			visibleQueue = visibleQueue,
			initiative = initiative,
			energy = {
				available = energy,
				allocated = allocated,
				remaining = energy - allocated,
			},
			canPlan = battle.phase == "PLANNING" and not roundState.committed,
			canRequestCommit = battle.phase == "PLANNING" and not roundState.committed,
			matchOutcome = snapshot.matchOutcome,
		},
	}
end

return table.freeze({ map = map })
