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

local function two(out)
	return out:match("^(%x+)\n(%x+)$")
end

local function log(plugin, head, tip, kind, ref, finish)
	plugin.head, plugin.tip = head, tip
	if head == tip then
		plugin.status = "ok"
		plugin.ahead = 0
		plugin.commits = {}
		plugin.label = kind == "tag" and ref or short(head)
		return finish()
	end
	git(
		{ "log", "--no-merges", "--max-count=4", "--pretty=format:%h%x09%s%x09%cr", head .. ".." .. tip },
		plugin.path,
		function(ok, text)
			plugin.commits = {}
			if ok then
				for line in vim.gsplit(text, "\n", { trimempty = true }) do
					local sha, subject, when = line:match("^(.-)\t(.*)\t(.*)$")
					if sha then
						plugin.commits[#plugin.commits + 1] = { sha = sha, subject = subject, when = when }
					end
				end
			end
			plugin.ahead = #plugin.commits
			plugin.status = "update"
			plugin.label = short(head) .. " \xe2\x86\x92 " .. (kind == "tag" and ref or short(tip))
			finish()
		end
	)
end

-- One rev-parse for HEAD and the ref vim.pack would check out. Tags are only
-- needed for a version range; everything else tracks a branch or a commit.
local function compare(plugin, finish)
	local version = plugin.version
	if version == nil then
		git({ "rev-parse", "--verify", "HEAD", "origin/HEAD" }, plugin.path, function(ok, out)
			local head, tip = ok and two(out) or nil
			if not head then
				plugin.status = "unknown"
				return finish()
			end
			log(plugin, head, tip, "branch", nil, finish)
		end)
	elseif type(version) == "string" then
		git({ "rev-parse", "--verify", "HEAD", "origin/" .. version }, plugin.path, function(ok, out)
			local head, tip = ok and two(out) or nil
			if head then
				return log(plugin, head, tip, "branch", version, finish)
			end
			git({ "rev-parse", "--verify", "HEAD", version }, plugin.path, function(ok_commit, commit_out)
				local head_commit, tip_commit = ok_commit and two(commit_out) or nil
				if not head_commit then
					plugin.status = "unknown"
					return finish()
				end
				log(plugin, head_commit, tip_commit, "commit", version, finish)
			end)
		end)
	else
		git({ "tag", "--list", "--sort=-v:refname" }, plugin.path, function(ok, out)
			if not ok then
				plugin.status = "unknown"
				return finish()
			end
			local tag
			for name in vim.gsplit(out, "\n", { trimempty = true }) do
				local parsed = vim.version.parse(name)
				if parsed and version:has(parsed) then
					tag = name
					break
				end
			end
			if not tag then
				plugin.status = "unknown"
				return finish()
			end
			git({ "rev-parse", "--verify", "HEAD", tag }, plugin.path, function(ok_tag, tag_out)
				local head, tip = ok_tag and two(tag_out) or nil
				if not head then
					plugin.status = "error"
					return finish()
				end
				log(plugin, head, tip, "tag", tag, finish)
			end)
		end)
	end
end

-- Fill status, ahead, and log. `done` runs from the scheduler.
function M.check(plugin, fetch, done)
	plugin.status = "checking"

	local function finish()
		vim.schedule(done)
	end

	if not fetch then
		return compare(plugin, finish)
	end
	local args = { "fetch", "--quiet", "--prune", "--no-tags", "origin" }
	if plugin.version ~= nil and type(plugin.version) ~= "string" then
		args = { "fetch", "--quiet", "--prune", "--tags", "origin" }
	end
	git(args, plugin.path, function()
		compare(plugin, finish)
	end)
end

return M
