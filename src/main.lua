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
    "https://raw.githubusercontent.com/%s/%s/main/",
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