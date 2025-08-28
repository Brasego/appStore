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
-- Helper: write a file, creating intermediate directories as needed
local function writeFile(fullPath, content)
  local dir = fs.getDir(fullPath)
  if dir ~= "" then fs.makeDir(dir) end
  local f = io.open(fullPath, "w")
  if not f then error("Cannot open " .. fullPath .. " for writing") end
  f:write(content)
  f:close()
end

-----------------------------------------------------------------
-- New downloader – respects a manifest (app.json) if present
local function downloadApp(repo)
  local baseRaw = string.format(
    "https://raw.githubusercontent.com/%s/%s/master/",
    USER, repo.name)

  -- -------------------------------------------------------------
  -- 1️⃣ Try to fetch the manifest first
  local manifestURL = baseRaw .. "app.json"
  local manifestResp = http.get(manifestURL, authHeader())
  local manifestData = nil

  if manifestResp then
    local raw = manifestResp.readAll()
    manifestResp.close()
    local ok, parsed = pcall(textutils.unserialiseJSON, raw)
    if ok and type(parsed) == "table" and parsed.files then
      manifestData = parsed
    else
      print("⚠️  app.json found but could not be parsed – falling back to single‑file mode.")
    end
  else
    -- No manifest – that's fine, we’ll just grab the default file.
    print("ℹ️  No app.json – downloading default src/main.lua")
  end

  -- -------------------------------------------------------------
  -- 2️⃣ Determine which files to download
  local filesToGet = {}
  if manifestData then
    for _, relPath in ipairs(manifestData.files) do
      table.insert(filesToGet, relPath)
    end
  else
    -- Legacy fallback – only the main entry point
    table.insert(filesToGet, "src/main.lua")
  end

  -- -------------------------------------------------------------
  -- 3️⃣ Download each file
  local destRoot = "/apps/" .. repo.name
  fs.makeDir(destRoot)   -- ensure the app folder exists

  for _, relPath in ipairs(filesToGet) do
    local rawURL = baseRaw .. relPath
    local resp = http.get(rawURL, authHeader())
    if not resp then
      error("Failed to fetch " .. relPath .. " from " .. rawURL)
    end
    local content = resp.readAll()
    resp.close()

    local destPath = destRoot .. "/" .. relPath
    writeFile(destPath, content)
    print("✓ Saved " .. destPath)
  end

  -- -------------------------------------------------------------
  -- 4️⃣ Remember the entry point for later convenience
  local entry = (manifestData and manifestData.entry) or "src/main.lua"
  local metaPath = destRoot .. "/.meta"
  writeFile(metaPath, entry)   -- simple one‑line file storing the entry point
  print("✅ " .. repo.name .. " installed. Entry point: " .. entry)
end

-----------------------------------------------------------------
-- Path creator: adds the program to the shell path in usr/bin, creates usr/bin if needed
local function ensureInPath(appName)
  local shellPath = shell.path("/")
  local binDir = "/usr/bin"
  if not fs.exists(binDir) then
    fs.makeDir(binDir)
  end
  local linkPath = binDir .. "/" .. appName
  if not fs.exists(linkPath) then
    open(appName, "w"):write(string.format('shell.run("/apps/%s/.main")\n', appName))
  end

end


-----------------------------------------------------------------
-- Main driver
local function main()
  local repos = fetchMinecraftRepos()
  if #repos == 0 then
    print("No repositories found with the '" .. TOPIC .. "' topic.")
    return
  end

  
  local repo = chooseRepo(repos)
  if not repo then print("Exiting.") return end
  local ok, err = pcall(downloadApp, repo)
  if not ok then print("Error: " .. err) end
  ensureInPath(repo.name)
  print("Et voilà !")
  print("\n---\n")
  
end

-----------------------------------------------------------------
main()