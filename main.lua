-- appstore.lua – a minimal GitHub‑backed app manager for ComputerCraft
-- ---------------------------------------------------------------
-- Prereqs:
--   • A GitHub personal access token stored in a file called "githubToken"
--     in the same directory as this script (or in /home).
--   • textutils.unserialiseJSON (CC 1.80+) or a bundled JSON lib.
-- ---------------------------------------------------------------

local user = "Brasego"   -- <-- replace with your GitHub user/org
local apiRoot = "https://api.github.com"
local tokenFile = "/disk/creds/githubToken"   -- keep this file private!

-- -----------------------------------------------------------------
-- Helper: read token (if you don’t want a token, just delete the header)
local function readToken()
  local f = io.open(TOKEN_FILE, "r")
  if not f then return nil end
  local token = f:read("*l")
  f:close()
  return token
end

local githubToken = readToken()

local function authHeader()
  if githubToken then
    return { ["Authorization"] = "token " .. githubToken }   -- Bearer style works too
  else
    return {}
  end
end

-- -----------------------------------------------------------------
-- Helper: perform a GET request and return parsed JSON (or nil+err)
local function getJSON(url)
  local response = http.get(url, authHeader())
  if not response then return nil, "HTTP request failed" end
  local body = response.readAll()
  response.close()
  local ok, data = pcall(textutils.unserialiseJSON, body)
  if not ok then return nil, "JSON parse error" end
  return data
end

-- -----------------------------------------------------------------
-- Step 1 – fetch list of repos for the user
local function fetchRepos()
  local url = API_ROOT .. "/users/" .. USER .. "/repos?per_page=100"
  local repos, err = getJSON(url)
  if not repos then error("Could not fetch repos: " .. tostring(err)) end
  return repos
end

-- -----------------------------------------------------------------
-- Step 2 – pretty‑print a selectable menu
local function chooseRepo(repos)
  print("\n=== Available apps (GitHub: " .. USER .. ") ===")
  for i, r in ipairs(repos) do
    print(string.format("%2d) %s%s", i, r.name,
          r.private and " (private)" or ""))
  end
  print(" 0) Exit")
  write("Select an app number: ")
  local choice = tonumber(read())
  if not choice or choice < 0 or choice > #repos then
    print("Invalid choice.")
    return nil
  elseif choice == 0 then
    return nil
  else
    return repos[choice]
  end
end

-- -----------------------------------------------------------------
-- Step 3 – download the app's main file (adjust if you store elsewhere)
local function downloadApp(repo)
  -- Assume the entry point is src/main.lua – you can change this path.
  local rawURL = string.format(
    "https://raw.githubusercontent.com/%s/%s/master/src/main.lua",
    USER, repo.name)

  print("Downloading " .. repo.name .. " …")
  local resp = http.get(rawURL, authHeader())
  if not resp then error("Failed to fetch file from " .. rawURL) end
  local code = resp.readAll()
  resp.close()

  -- Write to /apps/<repo-name>/main.lua (create dir if needed)
  local destDir = "/apps/" .. repo.name
  fs.makeDir(destDir)
  local destPath = destDir .. "/main.lua"
  local f = io.open(destPath, "w")
  f:write(code)
  f:close()
  print("Saved to " .. destPath)
end

-- -----------------------------------------------------------------
-- Main driver
local function main()
  local repos = fetchRepos()
  while true do
    local repo = chooseRepo(repos)
    if not repo then break end
    local ok, err = pcall(downloadApp, repo)
    if not ok then print("Error: " .. err) end
    print("\n---\n")
  end
  print("Goodbye!")
end

-- ---------------------------------------------------------------
main()