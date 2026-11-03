--!strict

-- Pure client-side ordering boundary for profile-backed DTOs. Profile revision
-- dominates request order; request order breaks ties at the same revision.

local ProfileStateCoordinator = {}

export type ReadToken = {
	resource: string,
	sequence: number,
	requestId: string,
}

local function integer(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value % 1 == 0
end

function ProfileStateCoordinator.new()
	local profileRevision: number? = nil
	local sequence = 0
	local resources = {}
	local activeMutation: any = nil
	local uncertainByFingerprint = {}
	local destroyed = false
	local service = {}

	local function resourceState(name: string)
		local current = resources[name]
		if current == nil then
			current = {
				value = nil,
				revision = nil,
				latestStarted = 0,
				latestApplied = 0,
				invalidated = true,
			}
			resources[name] = current
		end
		return current
	end

	local function observeRevision(revision: number, exceptResource: string?)
		if profileRevision == nil or revision > profileRevision then
			profileRevision = revision
			for name, resource in resources do
				if name ~= exceptResource and resource.revision ~= revision then
					resource.invalidated = true
				end
			end
		end
	end

	function service.revision(): number?
		return profileRevision
	end

	function service.beginRead(resource: string, requestId: string): ReadToken
		sequence += 1
		local current = resourceState(resource)
		current.latestStarted = sequence
		return {
			resource = resource,
			sequence = sequence,
			requestId = requestId,
		}
	end

	function service.applyRead(token: ReadToken, revision: number, value)
		if destroyed then
			return { applied = false, reason = "DESTROYED" }
		end
		if not integer(revision) then
			return { applied = false, reason = "INVALID_REVISION" }
		end
		local current = resourceState(token.resource)
		if profileRevision ~= nil and revision < profileRevision then
			return { applied = false, reason = "OLDER_PROFILE_REVISION" }
		end
		if current.revision ~= nil and revision < current.revision then
			return { applied = false, reason = "OLDER_RESOURCE_REVISION" }
		end
		if revision == current.revision and token.sequence < current.latestApplied then
			return { applied = false, reason = "OLDER_REQUEST_SEQUENCE" }
		end
		observeRevision(revision, token.resource)
		current.value = value
		current.revision = revision
		current.latestApplied = token.sequence
		current.invalidated = false
		return { applied = true, reason = "APPLIED" }
	end

	function service.applyMutationRevision(revision: number, affectedResources): boolean
		if not integer(revision) then
			return false
		end
		if profileRevision ~= nil and revision < profileRevision then
			return false
		end
		observeRevision(revision, nil)
		profileRevision = revision
		for _, name in affectedResources or {} do
			resourceState(name).invalidated = true
		end
		return true
	end

	function service.applyMutationResource(resource: string, revision: number, value): boolean
		if not integer(revision) or (profileRevision ~= nil and revision < profileRevision) then
			return false
		end
		observeRevision(revision, resource)
		local current = resourceState(resource)
		current.value = value
		current.revision = revision
		current.latestApplied = math.max(current.latestApplied, current.latestStarted)
		current.invalidated = false
		return true
	end

	function service.get(resource: string)
		return resourceState(resource).value
	end

	function service.resourceRevision(resource: string): number?
		return resourceState(resource).revision
	end

	function service.isFresh(resource: string): boolean
		local current = resourceState(resource)
		return current.value ~= nil
			and not current.invalidated
			and profileRevision ~= nil
			and current.revision == profileRevision
	end

	function service.invalidate(resource: string)
		resourceState(resource).invalidated = true
	end

	function service.beginMutation(operation: string, request): any
		if destroyed or activeMutation ~= nil then
			return nil
		end
		sequence += 1
		activeMutation = {
			sequence = sequence,
			operation = operation,
			request = request,
		}
		return activeMutation
	end

	function service.finishMutation(token): boolean
		if activeMutation ~= token then
			return false
		end
		activeMutation = nil
		return true
	end

	function service.mutationPending(): boolean
		return activeMutation ~= nil
	end

	function service.rememberUncertain(fingerprint: string, request)
		uncertainByFingerprint[fingerprint] = request
	end

	function service.uncertainRequest(fingerprint: string)
		return uncertainByFingerprint[fingerprint]
	end

	function service.clearUncertain(fingerprint: string)
		uncertainByFingerprint[fingerprint] = nil
	end

	function service.destroy()
		destroyed = true
		activeMutation = nil
		table.clear(uncertainByFingerprint)
	end

	return table.freeze(service)
end

return table.freeze(ProfileStateCoordinator)
