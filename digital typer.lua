require "import"
import "android.widget.*"
import "android.content.Intent"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"
import "android.view.View"
import "android.content.Context"
import "android.text.TextWatcher"
import "android.net.Uri"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.nio.channels.FileChannel"
import "android.os.SystemClock"
import "android.view.GestureDetector"
import "android.view.MotionEvent"
import "android.os.Environment"
import "com.androlua.Http"
import "cjson"

-- ============================================================
-- فائل راستے
-- ============================================================
local backupFolder = os.getenv("EXTERNAL_STORAGE") .. "/解说/Plugins/digital typer/backup"
local dictFile = backupFolder .. "/dictionary.txt"
local settingsFile = backupFolder .. "/digital_typer_settings.txt"
local dictBackupFile = backupFolder .. "/dictionary_backup.txt"
local settingsBackupFile = backupFolder .. "/digital_typer_settings_backup.txt"

-- ڈکشنری ٹیبل
local changeTable = {}

-- سیٹنگز
local settings = { punctuation = "newline", showLangDialog = true, autoCorrectUrdu = true }
local favouriteIndices = {}
local primaryLangCode = "en-PK"
local secondaryLangCode = "ur-PK"

-- ==================== GOOGLE GEMINI CONFIG ====================
local GEMINI_PREFS = "UniqueTyperAI"
local geminiPrefs = service.getSharedPreferences(GEMINI_PREFS, Context.MODE_PRIVATE)
local geminiEditor = geminiPrefs.edit()

local GEMINI_MODELS = {
    "Gemini 2.5 Flash",
    "Gemini 2.5 Pro",
    "Gemini 2.0 Flash"
}

local geminiApiDetails = {
    ["Gemini 2.5 Flash"] = { id = "models/gemini-2.5-flash", version = "v1beta" },
    ["Gemini 2.5 Pro"] = { id = "models/gemini-2.5-pro", version = "v1beta" },
    ["Gemini 2.0 Flash"] = { id = "models/gemini-2.0-flash", version = "v1beta" }
}

function getGeminiApiKey()
    return geminiPrefs.getString("gemini_apiKey", "")
end

function saveGeminiApiKey(key)
    geminiEditor.putString("gemini_apiKey", key)
    geminiEditor.commit()
end

function getGeminiModel()
    return geminiPrefs.getString("gemini_model", "Gemini 2.5 Flash")
end

function saveGeminiModel(model)
    geminiEditor.putString("gemini_model", model)
    geminiEditor.commit()
end

-- ==================== GROQ AI CONFIG ====================
local GROQ_PREFS = "GroqAITyper"
local groqPrefs = service.getSharedPreferences(GROQ_PREFS, Context.MODE_PRIVATE)
local groqEditor = groqPrefs.edit()

local GROQ_MODELS = {
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "mixtral-8x7b-32768",
    "gemma2-9b-it",
    "llama-guard-3-8b"
}

function getGroqApiKey()
    return groqPrefs.getString("groq_apiKey", "")
end

function saveGroqApiKey(key)
    groqEditor.putString("groq_apiKey", key)
    groqEditor.commit()
end

function getGroqModel()
    return groqPrefs.getString("groq_model", "llama-3.3-70b-versatile")
end

function saveGroqModel(model)
    groqEditor.putString("groq_model", model)
    groqEditor.commit()
end

-- ==================== SHARED AI SETTINGS ====================
local SHARED_PREFS = "AI_Shared"
local sharedPrefs = service.getSharedPreferences(SHARED_PREFS, Context.MODE_PRIVATE)
local sharedEditor = sharedPrefs.edit()

function getSelectedAIEngine()
    return sharedPrefs.getString("ai_engine", "gemini")
end

function saveSelectedAIEngine(engine)
    sharedEditor.putString("ai_engine", engine)
    sharedEditor.commit()
end

-- ★ Custom Instruction ★
function getCustomInstruction()
    return sharedPrefs.getString("custom_instruction", "")
end

function saveCustomInstruction(instruction)
    sharedEditor.putString("custom_instruction", instruction)
    sharedEditor.commit()
end

function isEmojiEnabled()
    return sharedPrefs.getBoolean("emojiEnabled", false)
end

function setEmojiEnabled(enabled)
    sharedEditor.putBoolean("emojiEnabled", enabled)
    sharedEditor.commit()
end

function isApiTypingEnabled()
    return sharedPrefs.getBoolean("apiTypingEnabled", true)
end

function setApiTypingEnabled(enabled)
    sharedEditor.putBoolean("apiTypingEnabled", enabled)
    sharedEditor.commit()
end

-- ==================== STRICT AI INSTRUCTION (NO EXTRA TEXT) ====================
local DEFAULT_INSTRUCTION = [[You are a professional text grammar and spelling correction tool. Correct the given raw spoken text strictly according to these rules:
1. Keep English words written in English script (e.g., if the text has words like "message", "thank you", "call", "audio", keep them in English alphabet/characters, DO NOT convert or transliterate them into Urdu script like "میسج").
2. Keep Urdu words strictly in Urdu script. Fix any spelling issues or bad word joints in Urdu.
3. Ensure proper spacing between words.
4. Do NOT add any introductory text, explanation, notes, extra pleasantries, greetings, apologies, or any additional words or sentences.
5. Do NOT add any emojis unless the user explicitly requested them.
6. Return ONLY the exact corrected sentence text output. No extra words before or after the corrected sentence. Do not add "Corrected text:" or any similar prefix. Just the corrected sentence.]]

-- ==================== API CALLS ====================
function testGeminiAPI(apiKey, model, callback)
    local url = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. apiKey
    Http.get(url, {}, function(status, data)
        if status == 200 then callback(true, "API key is valid!")
        else callback(false, "Invalid API key or error: " .. status) end
    end)
end

function callGeminiAPI(apiKey, model, prompt, callback)
    local modelInfo = geminiApiDetails[model]
    if not modelInfo then callback(nil, "Error: Model not found") return end
    
    local cleanKey = apiKey:gsub("%s+", "")
    local url = "https://generativelanguage.googleapis.com/" .. modelInfo.version .. "/" .. modelInfo.id .. ":generateContent?key=" .. cleanKey
    
    local systemInstruction = getCustomInstruction()
    if systemInstruction == "" then systemInstruction = DEFAULT_INSTRUCTION end
    
    local payload = {
        contents = {
            {
                parts = {
                    { text = prompt }
                }
            }
        },
        systemInstruction = {
            parts = {
                { text = systemInstruction }
            }
        }
    }
    
    local headers = { ["Content-Type"] = "application/json" }
    Http.post(url, cjson.encode(payload), headers, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.candidates and decoded.candidates[1] then
                local text = decoded.candidates[1].content and decoded.candidates[1].content.parts and decoded.candidates[1].content.parts[1] and decoded.candidates[1].content.parts[1].text
                if text then callback(text, nil) else callback(nil, "Invalid response from Gemini") end
            else callback(nil, "Failed to parse Gemini response") end
        else 
            callback(nil, "Gemini Error: " .. status .. "\nPlease verify that your Gemini API Key is correct.") 
        end
    end)
end

function testGroqAPI(apiKey, model, callback)
    local url = "https://api.groq.com/openai/v1/models"
    local headers = { ["Authorization"] = "Bearer " .. apiKey }
    Http.get(url, headers, function(status, data)
        if status == 200 then callback(true, "API key is valid!")
        elseif status == 401 then callback(false, "Invalid API key")
        else callback(false, "Error: " .. status) end
    end)
end

function callGroqAPI(apiKey, model, systemPrompt, userPrompt, callback)
    local url = "https://api.groq.com/openai/v1/chat/completions"
    local headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. apiKey }
    local messages = {}
    if systemPrompt ~= "" then table.insert(messages, {role = "system", content = systemPrompt}) end
    table.insert(messages, {role = "user", content = userPrompt})
    local payload = { model = model, messages = messages, max_tokens = 1024, temperature = 0.7 }
    Http.post(url, cjson.encode(payload), headers, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.choices and decoded.choices[1] then
                local text = decoded.choices[1].message.content
                if text then callback(text, nil) else callback(nil, "Invalid response from Groq") end
            else callback(nil, "Failed to parse Groq response") end
        elseif status == 401 then callback(nil, "Invalid API key. Please check your Groq API key")
        elseif status == 429 then callback(nil, "Rate limit exceeded. Please wait or check your quota")
        else callback(nil, "Groq Error: " .. status) end
    end)
end

-- ==================== PROMPTS ====================
function getGeminiPrompt(spokenText)
    local extra = isEmojiEnabled() and " After each sentence, add ONE relevant emoji." or " Do NOT add any emojis."
    return "Fix this spoken text keeping script languages intact (English words in English characters, Urdu in Urdu characters):" .. extra .. "\n\nInput Text: " .. spokenText
end

function cleanAIResponse(text)
    if not text then return "" end
    -- Remove common prefixes
    text = text:gsub("^[%s]*Corrected:?%s*", "")
    text = text:gsub("^[%s]*Output:?%s*", "")
    text = text:gsub("^[%s]*Here is the corrected text:?%s*", "")
    text = text:gsub("%s*$", "")
    -- Remove any extra sentence that might start with "I have corrected" etc. (simple heuristic)
    if text:find("^[A-Z][a-z]+%s+") then
        -- if it starts with a word like "I", "Here", "Please" then keep only first sentence?
        local firstSentence = text:match("^[^.]+[.]?")
        if firstSentence then text = firstSentence end
    end
    return text
end

function showErrorPopup(message)
    local dlg = LuaDialog(service)
    dlg.setTitle("API Error")
    dlg.setMessage(message)
    dlg.setButton("Cancel", function() dlg.dismiss() end)
    dlg.show()
end

-- ==================== AI PROCESSING ====================
function processWithAI(spokenText, callback)
    local engine = getSelectedAIEngine()
    if engine == "groq" then
        local apiKey = getGroqApiKey()
        if not apiKey or apiKey == "" then
            service.speak("Please set Groq API key in AI settings first")
            callback(spokenText)
            return
        end
        local model = getGroqModel()
        local systemPrompt = getCustomInstruction()
        if systemPrompt == "" then systemPrompt = DEFAULT_INSTRUCTION end
        callGroqAPI(apiKey, model, systemPrompt, spokenText, function(result, error)
            if error then showErrorPopup(error)
            else callback(cleanAIResponse(result)) end
        end)
    else
        local apiKey = getGeminiApiKey()
        if not apiKey or apiKey == "" then
            callback(spokenText)
            return
        end
        local model = getGeminiModel()
        local prompt = getGeminiPrompt(spokenText)
        callGeminiAPI(apiKey, model, prompt, function(result, error)
            if error then showErrorPopup(error)
            else callback(cleanAIResponse(result)) end
        end)
    end
end

-- ==================== AI SETTINGS DIALOG ====================
function showAISettingsDialog(mainDlg)
    local dlg = LuaDialog(service)
    dlg.setTitle("AI Engine Settings")
    dlg.setCancelable(true)
    
    local mainLayout = LinearLayout(service)
    mainLayout.setOrientation(1)
    mainLayout.setPadding(30, 20, 30, 20)
    
    local engineLabel = TextView(service)
    engineLabel.setText("Select AI Engine:")
    engineLabel.setTextSize(14)
    engineLabel.setTextColor(0xFFFFFFFF)
    engineLabel.setPadding(0, 0, 0, 10)
    mainLayout.addView(engineLabel)
    
    local engineSpinner = Spinner(service)
    local engines = {"Gemini", "Groq"}
    local engineAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, engines)
    engineAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    engineSpinner.setAdapter(engineAdapter)
    local currentEngine = getSelectedAIEngine()
    engineSpinner.setSelection(currentEngine == "groq" and 1 or 0)
    mainLayout.addView(engineSpinner)
    
    local settingsContainer = LinearLayout(service)
    settingsContainer.setOrientation(1)
    settingsContainer.setPadding(0, 20, 0, 0)
    mainLayout.addView(settingsContainer)
    
    local apiBtn = Button(service)
    local apiState = isApiTypingEnabled()
    apiBtn.setText(apiState and "Typing with API: ON" or "Typing with API: OFF")
    apiBtn.setTextSize(14)
    apiBtn.setBackgroundColor(0xFF333333)
    apiBtn.setPadding(0, 15, 0, 15)
    apiBtn.setOnClickListener(function()
        local newState = not isApiTypingEnabled()
        setApiTypingEnabled(newState)
        saveAllSettings()
        apiBtn.setText(newState and "Typing with API: ON" or "Typing with API: OFF")
        service.speak("API Typing " .. (newState and "enabled" or "disabled"))
    end)
    mainLayout.addView(apiBtn)
    
    local instrLabel = TextView(service)
    instrLabel.setText("Custom Instruction:")
    instrLabel.setTextSize(14)
    instrLabel.setTextColor(0xFFFFFFFF)
    instrLabel.setPadding(0, 0, 0, 10)
    mainLayout.addView(instrLabel)
    
    local instructionInput = EditText(service)
    instructionInput.setHint("Enter custom instruction for AI (leave empty for default)")
    instructionInput.setText(getCustomInstruction())
    instructionInput.setTextSize(14)
    instructionInput.setMinLines(3)
    instructionInput.setPadding(20, 15, 20, 15)
    instructionInput.setBackgroundColor(0xFF222222)
    local instrParams = LinearLayout.LayoutParams(-1, -2)
    instrParams.setMargins(0, 0, 0, 15)
    instructionInput.setLayoutParams(instrParams)
    mainLayout.addView(instructionInput)
    
    local buttonRow = LinearLayout(service)
    buttonRow.setOrientation(0)
    buttonRow.setPadding(0, 20, 0, 0)
    
    local saveBtn = Button(service)
    saveBtn.setText("SAVE")
    saveBtn.setTextSize(12)
    saveBtn.setBackgroundColor(0xFF4CAF50)
    saveBtn.setPadding(0, 15, 0, 15)
    saveBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    saveBtn.getLayoutParams().setMargins(5, 0, 5, 0)
    
    local backBtn = Button(service)
    backBtn.setText("GO BACK")
    backBtn.setTextSize(12)
    backBtn.setBackgroundColor(0xFFF44336)
    backBtn.setPadding(0, 15, 0, 15)
    backBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    backBtn.getLayoutParams().setMargins(5, 0, 0, 0)
    
    buttonRow.addView(saveBtn)
    buttonRow.addView(backBtn)
    mainLayout.addView(buttonRow)
    
    local function updateSettingsUI(engine)
        settingsContainer.removeAllViews()
        if engine == "groq" then
            local groqKeyLabel = TextView(service)
            groqKeyLabel.setText("Groq API Key:")
            groqKeyLabel.setTextSize(14)
            groqKeyLabel.setTextColor(0xFFFFFFFF)
            groqKeyLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(groqKeyLabel)
            
            local groqKeyInput = EditText(service)
            groqKeyInput.setHint("Enter Groq API Key")
            local savedGroqKey = getGroqApiKey()
            if savedGroqKey ~= "" then groqKeyInput.setText(savedGroqKey) end
            groqKeyInput.setTextSize(14)
            groqKeyInput.setPadding(20, 15, 20, 15)
            groqKeyInput.setBackgroundColor(0xFF222222)
            local groqKeyParams = LinearLayout.LayoutParams(-1, -2)
            groqKeyParams.setMargins(0, 0, 0, 15)
            groqKeyInput.setLayoutParams(groqKeyParams)
            settingsContainer.addView(groqKeyInput)
            
            local groqModelLabel = TextView(service)
            groqModelLabel.setText("Select Model:")
            groqModelLabel.setTextSize(14)
            groqModelLabel.setTextColor(0xFFFFFFFF)
            groqModelLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(groqModelLabel)
            
            local groqModelSpinner = Spinner(service)
            local groqAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GROQ_MODELS)
            groqAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            groqModelSpinner.setAdapter(groqAdapter)
            local currentGroqModel = getGroqModel()
            for i, m in ipairs(GROQ_MODELS) do
                if m == currentGroqModel then groqModelSpinner.setSelection(i-1) break end
            end
            local groqSpinnerParams = LinearLayout.LayoutParams(-1, -2)
            groqSpinnerParams.setMargins(0, 0, 0, 15)
            groqModelSpinner.setLayoutParams(groqSpinnerParams)
            settingsContainer.addView(groqModelSpinner)
            
            saveBtn.setOnClickListener(function()
                local key = groqKeyInput.getText().toString()
                local model = GROQ_MODELS[groqModelSpinner.getSelectedItemPosition() + 1]
                if key ~= "" then saveGroqApiKey(key) end
                if model then saveGroqModel(model) end
                saveCustomInstruction(instructionInput.getText().toString())
                saveSelectedAIEngine("groq")
                saveAllSettings()
                service.speak("Settings saved")
                dlg.dismiss()
                if mainDlg then mainDlg.show() end
            end)
        else
            local geminiKeyLabel = TextView(service)
            geminiKeyLabel.setText("Gemini API Key:")
            geminiKeyLabel.setTextSize(14)
            geminiKeyLabel.setTextColor(0xFFFFFFFF)
            geminiKeyLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(geminiKeyLabel)
            
            local geminiKeyInput = EditText(service)
            geminiKeyInput.setHint("Enter Gemini API Key")
            local savedGeminiKey = getGeminiApiKey()
            if savedGeminiKey ~= "" then geminiKeyInput.setText(savedGeminiKey) end
            geminiKeyInput.setTextSize(14)
            geminiKeyInput.setPadding(20, 15, 20, 15)
            geminiKeyInput.setBackgroundColor(0xFF222222)
            local geminiKeyParams = LinearLayout.LayoutParams(-1, -2)
            geminiKeyParams.setMargins(0, 0, 0, 15)
            geminiKeyInput.setLayoutParams(geminiKeyParams)
            settingsContainer.addView(geminiKeyInput)
            
            local geminiModelLabel = TextView(service)
            geminiModelLabel.setText("Select Model:")
            geminiModelLabel.setTextSize(14)
            geminiModelLabel.setTextColor(0xFFFFFFFF)
            geminiModelLabel.setPadding(0, 0, 0, 10)
            settingsContainer.addView(geminiModelLabel)
            
            local geminiModelSpinner = Spinner(service)
            local geminiAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GEMINI_MODELS)
            geminiAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
            geminiModelSpinner.setAdapter(geminiAdapter)
            local currentGeminiModel = getGeminiModel()
            for i, m in ipairs(GEMINI_MODELS) do
                if m == currentGeminiModel then geminiModelSpinner.setSelection(i-1) break end
            end
            local geminiSpinnerParams = LinearLayout.LayoutParams(-1, -2)
            geminiSpinnerParams.setMargins(0, 0, 0, 15)
            geminiModelSpinner.setLayoutParams(geminiSpinnerParams)
            settingsContainer.addView(geminiModelSpinner)
            
            saveBtn.setOnClickListener(function()
                local key = geminiKeyInput.getText().toString()
                local model = GEMINI_MODELS[geminiModelSpinner.getSelectedItemPosition() + 1]
                if key ~= "" then saveGeminiApiKey(key) end
                if model then saveGeminiModel(model) end
                saveCustomInstruction(instructionInput.getText().toString())
                saveSelectedAIEngine("gemini")
                saveAllSettings()
                service.speak("Settings saved")
                dlg.dismiss()
                if mainDlg then mainDlg.show() end
            end)
        end
    end
    
    engineSpinner.setOnItemSelectedListener({
        onItemSelected = function(parent, view, position, id)
            local selectedEngine = engines[position+1]:lower()
            updateSettingsUI(selectedEngine)
        end,
        onNothingSelected = function() end
    })
    
    updateSettingsUI(currentEngine)
    
    backBtn.setOnClickListener(function()
        dlg.dismiss()
        if mainDlg then mainDlg.show() end
    end)
    
    local scrollView = ScrollView(service)
    scrollView.addView(mainLayout)
    dlg.setView(scrollView)
    dlg.show()
end

-- ============================================================
-- زبانیں
-- ============================================================
local allLanguages = {
  {name = "English (Pakistan)", code = "en-PK"},
  {name = "Hindi (India)", code = "hi-IN"},
  {name = "Urdu (Pakistan)", code = "ur-PK"},
  {name = "Arabic (Saudi Arabia)", code = "ar-SA"},
}

local languageItems = {}
local languageCodes = {}
for i, lang in ipairs(allLanguages) do
  languageItems[i] = lang.name
  languageCodes[i] = lang.code
end

-- ============================================================
-- Helper functions
-- ============================================================
function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

function copyFile(source, dest)
  local src = File(source)
  local dst = File(dest)
  if src.exists() then
    local inChannel = FileInputStream(src).getChannel()
    local outChannel = FileOutputStream(dst).getChannel()
    inChannel.transferTo(0, inChannel.size(), outChannel)
    inChannel.close()
    outChannel.close()
    return true
  end
  return false
end

function getFileSize(path)
  local f = File(path)
  if f.exists() then return f.length() else return 0 end
end

function dumpTable(t, indent)
  indent = indent or 0
  local spaces = string.rep(" ", indent)
  if type(t) == "table" then
    local items = {}
    for k, v in pairs(t) do
      local key = (type(k) == "string" and string.format("%q", k)) or tostring(k)
      table.insert(items, string.format("%s[%s]=%s", spaces, key, dumpTable(v, indent+2)))
    end
    if #items == 0 then return "{}" else
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spaces .. "}"
    end
  elseif type(t) == "string" then return string.format("%q", t) else return tostring(t) end
end

function escapePattern(str)
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- ============================================================
-- DICTIONARY FUNCTIONS
-- ============================================================
function cleanCorruptedDictionaryEntries()
  if not changeTable then return end
  local cleanedTable = {}
  for wrong, correct in pairs(changeTable) do
    local isWrongValid = wrong and wrong ~= "" and utf8 and utf8.len(wrong) > 1
    local isCorrectValid = correct and correct ~= "" and utf8 and utf8.len(correct) > 1
    
    if isWrongValid and isCorrectValid then
      cleanedTable[wrong] = correct
    end
  end
  changeTable = cleanedTable
end

-- Add common Alif Madda words to dictionary
function addAlifMaddaWords()
  local alifMaddaMap = {
    ["اپ"] = "آپ",
    ["اج"] = "آج",
    ["انا"] = "آنا",
    ["ادمی"] = "آدمی",
    ["اسمان"] = "آسمان",
    ["اگ"] = "آگ",
    ["اٹا"] = "آٹا",
    ["استان"] = "آستان",
    ["اہ"] = "آہ",
    ["ارام"] = "آرام",
    ["ازما"] = "آزما",
    ["باد"] = "آباد",
  }
  for wrong, correct in pairs(alifMaddaMap) do
    if not changeTable[wrong] then
      changeTable[wrong] = correct
    end
  end
  saveDictionary()
end

function loadDictionary()
  local f = io.open(dictFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      content = content:gsub("^\239\187\191", "")
      local func = loadstring("return " .. content)
      if not func then func = loadstring(content) end
      if func then
        local dict = func()
        if type(dict) == "table" then
          changeTable = dict
          cleanCorruptedDictionaryEntries()
          -- Ensure common Alif Madda words exist
          addAlifMaddaWords()
          return
        end
      end
    end
  end
  changeTable = {}
  addAlifMaddaWords()
end

-- FIXED: Clear All کرنے پر اب مستقل فائل میں بھی ڈیٹا ڈیلیٹ (Save) ہوگا
function clearAllDictionary()
  changeTable = {}
  addAlifMaddaWords() -- re-add common words after clearing
  saveDictionary()
end

function saveDictionary()
  ensureBackupFolder()
  cleanCorruptedDictionaryEntries()
  local f = io.open(dictFile, "w")
  if f then
    local items = {}
    for w, c in pairs(changeTable) do
      table.insert(items, string.format("[%q]=%q", w, c))
    end
    f:write("{" .. table.concat(items, ",") .. "}")
    f:close()
    return true
  end
  return false
end

function addToDictionary(wrongWord, correctWord)
  if wrongWord and correctWord and wrongWord ~= "" and correctWord ~= "" then
    if utf8 and (utf8.len(wrongWord) <= 1 or utf8.len(correctWord) <= 1) then return false end
    changeTable[wrongWord] = correctWord
    saveDictionary()
    return true
  end
  return false
end

function deleteFromDictionary(wrongWord)
  if changeTable[wrongWord] then
    changeTable[wrongWord] = nil
    saveDictionary()
    return true
  end
  return false
end

-- ڈکشنری متبادل لاجک جو الفاظ کو تبدیل کرتی ہے
function applyDictionaryReplacements(text)
  if not text or text == "" then return text end
  local result = text
  for wrong, correct in pairs(changeTable) do
    if wrong and wrong ~= "" and correct and correct ~= "" then
      local pattern = "%f[%a%d\128-\255]" .. escapePattern(wrong) .. "%f[%s%p\0]"
      local ok, replaced = pcall(function() return result:gsub(pattern, correct) end)
      if ok then result = replaced else
        local patternSimple = escapePattern(wrong)
        result = result:gsub(patternSimple, correct)
      end
    end
  end
  return result
end

-- ڈکشنری مینیجر مینو (اصل لاجک اور لے آؤٹ)
function showDictionaryManager()
  local dlg = LuaDialog(service)
  dlg.setTitle("Digital Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { Button; text = "Add Word"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showAddWordDialog() end; };
    { Button; text = "View / Delete Words"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() showViewWordsDialog() end; };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showAddWordDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Add Word Replacement")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "20dp";
    { TextView; text = "Wrong Word Spoken:"; };
    { EditText; id = "wrongInput"; layout_width = "fill"; layout_marginBottom = "15dp"; };
    { TextView; text = "Correct Word to Replace With:"; };
    { EditText; id = "correctInput"; layout_width = "fill"; layout_marginBottom = "20dp"; };
    { LinearLayout; orientation = "horizontal"; layout_width = "fill";
      { Button; text = "Save"; layout_width = "0dp"; layout_weight = 1; onClick = function()
          local w = wrongInput.getText().toString():trim()
          local c = correctInput.getText().toString():trim()
          if w ~= "" and c ~= "" then
            if addToDictionary(w, c) then
              service.speak("Saved successfully")
              dlg.dismiss()
            else
              service.speak("Failed to save. Words too short.")
            end
          else
            service.speak("Fields cannot be empty")
          end
        end;
      };
      { Button; text = "Cancel"; layout_width = "0dp"; layout_weight = 1; onClick = function() dlg.dismiss() end; };
    };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showViewWordsDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Dictionary Words")
  
  local list = ListView(service)
  local wordsList = {}
  local rawKeys = {}
  
  for k, v in pairs(changeTable) do
    table.insert(rawKeys, k)
    table.insert(wordsList, k .. " -> " .. v)
  end
  
  local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, wordsList)
  list.setAdapter(adapter)
  
  list.setOnItemClickListener(function(parent, view, position, id)
    local selectedKey = rawKeys[position+1]
    local askDlg = LuaDialog(service)
    askDlg.setTitle("Delete Entry")
    askDlg.setMessage("Do you want to delete this word replacement?")
    askDlg.setButton("Delete", function()
      deleteFromDictionary(selectedKey)
      service.speak("Deleted")
      askDlg.dismiss()
      dlg.dismiss()
      showViewWordsDialog()
    end)
    askDlg.setButton2("Cancel", function() askDlg.dismiss() end)
    askDlg.show()
  end)
  
  -- FIXED: Empty بٹن پر اب مستقل طور پر ڈیٹا فائل سے صاف ہوگا
  dlg.setButton("Empty", function()
    local confirmDlg = LuaDialog(service)
    confirmDlg.setTitle("Clear All")
    confirmDlg.setMessage("Are you sure you want to clear the entire dictionary?")
    confirmDlg.setButton("Clear All", function()
      clearAllDictionary()
      service.speak("Dictionary cleared completely")
      confirmDlg.dismiss()
      dlg.dismiss()
    end)
    confirmDlg.setButton2("Cancel", function() confirmDlg.dismiss() end)
    confirmDlg.show()
  end)
  
  dlg.setButton2("Close", function() dlg.dismiss() end)
  dlg.setView(list)
  dlg.show()
end

-- ============================================================
-- اسمارٹ لرننگ لاجک
-- ============================================================
function learnFromAI(rawText, aiText)
  if not rawText or not aiText then return end

  local function clean(w)
    return (w:gsub("^[%p%s،۔?!" .. "]+", ""):gsub("[%p%s%،۔?!" .. "]+$", ""))
  end

  local rawWords = {}
  for w in rawText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" and utf8 and utf8.len(cw) > 1 then table.insert(rawWords, cw) end
  end

  local aiWords = {}
  for w in aiText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" and utf8 and utf8.len(cw) > 1 then table.insert(aiWords, cw) end
  end

  -- صورتِ حال 1: جب API چل رہی ہو اور لفظ تبدیل ہوا ہو
  if rawText ~= aiText then
    local maxLoop = math.min(#rawWords, #aiWords)
    for i = 1, maxLoop do
      local rw = rawWords[i]
      local aw = aiWords[i]
      if rw ~= aw then
        if rw:find("^ا") and aw:find("^آ") then
          addToDictionary(rw, aw)
        elseif rw:find("^%a+$") or aw:find("^%a+$") then
          addToDictionary(rw, aw)
        end
      end
    end
  else
    -- صورتِ حال 2: جب API بند ہو (Without API) اور ٹیکسٹ بالکل سیم ہو
    for i = 1, #rawWords do
      local word = rawWords[i]
      if word:find("^ا") and not word:find("^آ") then
        local correctedWord = word:gsub("^ا", "آ")
        addToDictionary(word, correctedWord)
      elseif word:find("^%a+$") then
        addToDictionary(word, word)
      end
    end
  end
end

-- ============================================================
-- زبان کا نام حاصل کرنے والا ہیلپر
-- ============================================================
function getLanguageNameFromCode(code)
  for _, lang in ipairs(allLanguages) do
    if lang.code == code then return lang.name end
  end
  return code
end

function showLanguagePicker(callback)
  local dlg = LuaDialog(service)
  dlg.setTitle("Select Language")
  local list = ListView(service)
  local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, languageItems)
  list.setAdapter(adapter)
  list.setOnItemClickListener(function(parent, view, position, id)
    local selectedCode = languageCodes[position+1]
    local selectedName = languageItems[position+1]
    callback(selectedCode, selectedName)
    service.speak("Selected " .. selectedName)
    dlg.dismiss()
  end)
  dlg.setView(list)
  dlg.show()
end

function showBackupRestoreDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Backup / Restore")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { Button; text = "Backup Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupDictionary() end; };
    { Button; text = "Backup Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupSettings() end; };
    { Button; text = "Restore Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        if copyFile(dictBackupFile, dictFile) then
          loadDictionary()
          service.speak("Dictionary restored successfully")
        else
          service.speak("No backup found")
        end
      end;
    };
    { Button; text = "Restore Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        if copyFile(settingsBackupFile, settingsFile) then
          loadAllSettings()
          service.speak("Settings restored successfully")
        else
          service.speak("No backup found")
        end
      end;
    };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- SETTINGS FUNCTIONS
-- ============================================================
function loadAllSettings()
  local f = io.open(settingsFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      content = content:gsub("^\239\187\191", "")
      local func = loadstring(content)
      if func then
        local data = func()
        if type(data) == "table" then
          primaryLangCode = data.primary or "en-PK"
          secondaryLangCode = data.secondary or "ur-PK"
          favouriteIndices = data.favourites or {}
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.autoCorrectUrdu = true
          
          if data.apiTypingEnabled ~= nil then
            setApiTypingEnabled(data.apiTypingEnabled)
          end
          return true
        end
      end
    end
  end
  return false
end

function saveAllSettings()
  ensureBackupFolder()
  local allSettings = {
    primary = primaryLangCode,
    secondary = secondaryLangCode,
    favourites = favouriteIndices,
    punctuation = settings.punctuation,
    showLangDialog = settings.showLangDialog,
    autoCorrectUrdu = settings.autoCorrectUrdu,
    apiTypingEnabled = isApiTypingEnabled()
  }
  local content = "return " .. dumpTable(allSettings)
  local f = io.open(settingsFile, "w")
  if f then
    f:write(content)
    f:close()
    return true
  end
  return false
end

function applyEndPunctuation(text)
  if settings.punctuation == "none" then return text
  elseif settings.punctuation == "dot_only" then
    if not text:match("[.!?]$") then return text .. "." end
  elseif settings.punctuation == "space_only" then
    if not text:match("%s$") then return text .. " " end
  elseif settings.punctuation == "newline" then
    if not text:match("\n$") then return text .. "\n" end
  end
  return text
end

-- ============================================================
-- FIXED: PUNCTUATION SETTINGS DIALOG (button click ab kaam karega)
-- ============================================================
function showPunctuationDialog()
    local dlg = LuaDialog(service)
    dlg.setTitle("Punctuation Settings")
    
    local options = {"None", "Dot Only (.)", "Space Only ( )", "New Line (\\n)"}
    local codes = {"none", "dot_only", "space_only", "newline"}
    
    -- موجودہ ویلیو کے مطابق اسپنر میں پوزیشن
    local currentCode = settings.punctuation or "newline"
    local currentIndex = 0
    for i, code in ipairs(codes) do
        if code == currentCode then
            currentIndex = i - 1
            break
        end
    end
    
    -- Spinner banayein
    local spinner = Spinner(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, options)
    adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    spinner.setAdapter(adapter)
    spinner.setSelection(currentIndex)
    
    -- LinearLayout (main container)
    local layout = LinearLayout(service)
    layout.setOrientation(1)
    layout.setPadding(40, 30, 40, 30)
    
    -- Heading TextView
    local heading = TextView(service)
    heading.setText("Choose punctuation style:")
    heading.setTextSize(16)
    heading.setTextColor(0xFFFFFFFF)
    heading.setPadding(0, 0, 0, 20)
    layout.addView(heading)
    
    -- Spinner add karein
    layout.addView(spinner)
    
    -- Save button
    local saveBtn = Button(service)
    saveBtn.setText("Save")
    saveBtn.setTextSize(14)
    saveBtn.setBackgroundColor(0xFF4CAF50)
    saveBtn.setPadding(0, 15, 0, 15)
    local btnParams = LinearLayout.LayoutParams(-1, -2)
    btnParams.topMargin = 30
    saveBtn.setLayoutParams(btnParams)
    layout.addView(saveBtn)
    
    -- Button click listener (ab yeh kaam karega)
    saveBtn.setOnClickListener(function()
        local selectedPos = spinner.getSelectedItemPosition()
        settings.punctuation = codes[selectedPos + 1]
        saveAllSettings()
        service.speak("Punctuation set to " .. options[selectedPos + 1])
        dlg.dismiss()
    end)
    
    dlg.setView(layout)
    dlg.show()
end

-- ============================================================
-- Voice typing
-- ============================================================
function startVoiceTyping(langCode)
  local speechRec = SpeechRecognizer.createSpeechRecognizer(service.getApplicationContext())
  local listener = RecognitionListener {
    onResults = function(results)
      local res = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if res and res.size() > 0 then
        local rawText = res.get(0)
        
        local function fallback(textToUse)
          local finalText = textToUse or rawText
          learnFromAI(rawText, finalText)
          finalText = applyDictionaryReplacements(finalText)
          finalText = applyEndPunctuation(finalText)
          service.insertText(service.getEditText(), finalText)
          service.speak(finalText)
        end
        
        if isApiTypingEnabled() then
          processWithAI(rawText, function(aiText)
            if aiText and aiText ~= "" then
              learnFromAI(rawText, aiText)
              local finalText = applyDictionaryReplacements(aiText)
              finalText = applyEndPunctuation(finalText)
              service.insertText(service.getEditText(), finalText)
              service.speak(finalText)
            else
              fallback(rawText)
            end
          end)
        else
          fallback(rawText)
        end
      end
      speechRec.destroy()
    end,
    onError = function() speechRec.destroy() end,
  }
  local intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
  intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, langCode)
  speechRec.setRecognitionListener(listener)
  speechRec.startListening(intent)
end

function showTypingDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Voice Typing")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; text = "Primary (" .. getLanguageNameFromCode(primaryLangCode) .. ")"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss() startVoiceTyping(primaryLangCode) end; };
    { Button; text = "Swap Languages"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        local temp = primaryLangCode
        primaryLangCode = secondaryLangCode
        secondaryLangCode = temp
        saveAllSettings()
        dlg.dismiss()
        showTypingDialog()
      end;
    };
    { Button; text = "Secondary (" .. getLanguageNameFromCode(secondaryLangCode) .. ")"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss() startVoiceTyping(secondaryLangCode) end; };
    { Button; text = "Settings"; layout_width = "fill"; onClick = function() dlg.dismiss() showMainMenu() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- MAIN MENU (Favourite Languages button removed)
-- ============================================================
function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("digital typer")
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "toggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Set Primary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) primaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Set Secondary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) secondaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Digital Dictionary"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showDictionaryManager() end; };
    -- Favourite Languages button removed
    { Button; text = "Punctuation Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showPunctuationDialog() end; };
    { Button; text = "AI Engine Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() dlg.dismiss() showAISettingsDialog(dlg) end; };
    { Button; text = "Backup / Restore"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showBackupRestoreDialog() end; };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layoutTable)
  local function updateUI() toggleBtn.setText(settings.showLangDialog and "Show dialog: ON" or "Show dialog: OFF") end
  toggleBtn.onClick = function() settings.showLangDialog = not settings.showLangDialog saveAllSettings() updateUI() end
  updateUI()
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- Entry Point
-- ============================================================
loadDictionary()
loadAllSettings()

if service.getEditText() then
  if settings.showLangDialog then showTypingDialog() else startVoiceTyping(primaryLangCode) end
else
  showMainMenu()
end