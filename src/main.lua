-- appstore.lua – Minecraft‑topic filtered app manager for ComputerCraft
-- ---------------------------------------------------------------
-- Prereqs:
--   • A GitHub personal access token (PAT) saved in github_token (optional but
--     strongly recommended – it lifts the 60‑req/hour limit and lets you query
--     private repos if you ever need them).
--   • textutils.unserialiseJSON (built‑in from CC 1.80+) or a bundled JSON lib.
-- ---------------------------------------------------------------

local USER = "Brasego"   -- <<< replace with your GitHub login
local TOPIC = "Minecraft"             -- the topic/tag you use on GitHub
local API_ROOT = "https://api.github.com"
local TOKEN_FILE = "/disk/creds/github_token"   -- keep this file private!

-----------------------------------------------------------------
-- Helper: read the PAT (if you have one)
local function readToken()
  local f = io.open(TOKEN_FILE, "r")
  if not f then return nil end
  local token = f:read("*l")
  f:close()
  return token
end

local GITHUB_TOKEN = readToken()

local function authHeader()
  if GITHUB_TOKEN then
    return { ["Authorization"] = "token " .. GITHUB_TOKEN }
  else
    return {}
  end
end

-----------------------------------------------------------------
-- Helper: generic GET → parsed JSON
local function getJSON(url)
  local response = http.get(url, authHeader())
  if not response then return nil, "HTTP request failed" end
  local body = response.readAll()
  response.close()
  local ok, data = pcall(textutils.unserialiseJSON, body)
  if not ok then return nil, "JSON parse error" end
  return data
end

-----------------------------------------------------------------
-- Step 1 – fetch ONLY repos that carry the desired topic
local function fetchMinecraftRepos()
  -- Encode the query components (spaces become %20, etc.)
  local query = string.format("user:%s+topic:%s", USER, TOPIC)
  local url = API_ROOT .. "/search/repositories?q=" .. query .. "&per_page=100"
  local result, err = getJSON(url)
  if not result then error("GitHub search failed: " .. tostring(err)) end
  -- `items` holds the array of matching repositories
  return result.items or {}
end

-----------------------------------------------------------------
-- Step 2 – menu for picking a repo
local function chooseRepo(repos)
  print("\n=== Minecraft‑topic apps (GitHub: " .. USER .. ") ===")
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

-----------------------------------------------------------------
-- Step 3 – download the app’s entry file
local function downloadApp(repo)
  -- Adjust this path if your apps store the entry point elsewhere.
  local rawURL = string.format(
    "https://raw.githubusercontent.com/%s/%s/main/src/main.lua",
    USER, repo.name)

  print("Downloading " .. repo.name .. " …")
  local resp = http.get(rawURL, authHeader())
  if not resp then error("Failed to fetch file from " .. rawURL) end
  local code = resp.readAll()
  resp.close()

  local destDir = "/apps/" .. repo.name
  fs.makeDir(destDir)
  local destPath = destDir .. "/main.lua"
  local f = io.open(destPath, "w")
  f:write(code)
  f:close()
  print("Saved to " .. destPath)
end

-----------------------------------------------------------------
-- Main driver
local function main()
  local repos = fetchMinecraftRepos()
  if #repos == 0 then
    print("No repositories found with the '" .. TOPIC .. "' topic.")
    return
  end

  while true do
    local repo = chooseRepo(repos)
    if not repo then break end
    local ok, err = pcall(downloadApp, repo)
    if not ok then print("Error: " .. err) end
    print("\n---\n")
  end
  print(" Oyoyo!")
end

-----------------------------------------------------------------
main()