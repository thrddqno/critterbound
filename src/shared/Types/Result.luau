--!strict

export type DomainError = {
	code: string,
	message: string,
	path: string?,
}

export type Success<T> = {
	ok: true,
	value: T,
}

export type Failure = {
	ok: false,
	errors: { DomainError },
}

export type Result<T> = Success<T> | Failure

local function success<T>(value: T): Success<T>
	return table.freeze({
		ok = true,
		value = value,
	})
end

local function failure(code: string, message: string, path: string?): Failure
	return table.freeze({
		ok = false,
		errors = table.freeze({
			table.freeze({
				code = code,
				message = message,
				path = path,
			}),
		}),
	})
end

local function failures(errors: { DomainError }): Failure
	local frozenErrors = table.create(#errors)

	for index, domainError in errors do
		frozenErrors[index] = table.freeze({
			code = domainError.code,
			message = domainError.message,
			path = domainError.path,
		})
	end

	return table.freeze({
		ok = false,
		errors = table.freeze(frozenErrors),
	})
end

return table.freeze({
	success = success,
	failure = failure,
	failures = failures,
})
