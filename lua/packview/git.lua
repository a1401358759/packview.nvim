-- Read-only git. vim.pack owns clone, checkout, and the lockfile.

local M = {}

local function git(args, cwd, cb)
	vim.system({ "git", "-c", "gc.auto=0", unpack(args) }, { cwd = cwd, text = true }, function(res)
		cb(res.code == 0, vim.trim(res.stdout or ""), res.stderr or "")
	end)
end

local function short(sha)
	return sha ~= "" and sha:sub(1, 7) or ""
end

-- The ref vim.pack would check out: default branch, a branch, a tag or commit,
-- or the newest tag inside a version range.
local function target(plugin, cb)
	local version = plugin.version
	if version == nil then
		git({ "rev-parse", "--abbrev-ref", "origin/HEAD" }, plugin.path, function(ok, out)
			cb(ok and out ~= "" and out or nil, "branch")
		end)
	elseif type(version) == "string" then
		git({ "branch", "--remote", "--list", "origin/" .. version }, plugin.path, function(ok, out)
			cb(ok and out ~= "" and ("origin/" .. version) or version, ok and out ~= "" and "branch" or "commit")
		end)
	else
		git({ "tag", "--list", "--sort=-v:refname" }, plugin.path, function(ok, out)
			if not ok then
				return cb(nil)
			end
			for tag in vim.gsplit(out, "\n", { trimempty = true }) do
				local parsed = vim.version.parse(tag)
				if parsed and version:has(parsed) then
					return cb(tag, "tag")
				end
			end
			cb(nil)
		end)
	end
end

-- Fill status, ahead, and log. `done` runs from the scheduler.
function M.check(plugin, fetch, done)
	plugin.status = "checking"

	local function finish()
		vim.schedule(done)
	end

	local function compare()
		target(plugin, function(ref, kind)
			if not ref then
				plugin.status = "unknown"
				return finish()
			end
			git({ "rev-parse", "HEAD" }, plugin.path, function(ok_head, head)
				git({ "rev-list", "-1", ref }, plugin.path, function(ok_ref, tip)
					if not (ok_head and ok_ref) or head == "" or tip == "" then
						plugin.status = "error"
						return finish()
					end
					plugin.head, plugin.tip = head, tip
					if head == tip then
						plugin.status = "ok"
						plugin.label = kind == "tag" and ref or short(head)
						return finish()
					end
					git(
						{ "log", "--no-merges", "--pretty=format:%h%x09%s%x09%cr", head .. ".." .. tip },
						plugin.path,
						function(ok, log)
							plugin.commits = {}
							if ok then
								for line in vim.gsplit(log, "\n", { trimempty = true }) do
									local sha, subject, when = line:match("^(.-)\t(.*)	(.*)$")
									if sha then
										plugin.commits[#plugin.commits + 1] = { sha = sha, subject = subject, when = when }
									end
								end
							end
							plugin.ahead = #plugin.commits
							plugin.status = "update"
							plugin.label = short(head) .. " → " .. (kind == "tag" and ref or short(tip))
							finish()
						end
					)
				end)
			end)
		end)
	end

	if fetch then
		git({ "fetch", "--quiet", "--tags", "--force", "origin" }, plugin.path, compare)
	else
		compare()
	end
end

return M
