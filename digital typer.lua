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
local primaryLangCode = "en-US"
local secondaryLangCode = "ur-PK"

-- ==================== GOOGLE GEMINI ONLY CONFIG ====================
local AI_PREFS = "UniqueTyperAI"
local aiPrefs = service.getSharedPreferences(AI_PREFS, Context.MODE_PRIVATE)
local aiEditor = aiPrefs.edit()

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
    return aiPrefs.getString("gemini_apiKey", "")
end

function saveGeminiApiKey(key)
    aiEditor.putString("gemini_apiKey", key)
    aiEditor.commit()
end

function getGeminiModel()
    return aiPrefs.getString("gemini_model", "Gemini 2.5 Flash")
end

function saveGeminiModel(model)
    aiEditor.putString("gemini_model", model)
    aiEditor.commit()
end

function isEmojiEnabled()
    return aiPrefs.getBoolean("emojiEnabled", false)
end

function setEmojiEnabled(enabled)
    aiEditor.putBoolean("emojiEnabled", enabled)
    aiEditor.commit()
end

function isApiTypingEnabled()
    return aiPrefs.getBoolean("apiTypingEnabled", true)
end

function setApiTypingEnabled(enabled)
    aiEditor.putBoolean("apiTypingEnabled", enabled)
    aiEditor.commit()
end

function testGeminiAPI(apiKey, model, callback)
    local url = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. apiKey
    Http.get(url, {}, function(status, data)
        if status == 200 then
            callback(true, "API key is valid!")
        else
            callback(false, "Invalid API key or error: " .. status)
        end
    end)
end

function callGeminiAPI(apiKey, model, prompt, callback)
    local modelInfo = geminiApiDetails[model]
    if not modelInfo then
        callback(nil, "Error: Model not found")
        return
    end
    local url = "https://generativelanguage.googleapis.com/" .. modelInfo.version .. "/" .. modelInfo.id .. ":generateContent?key=" .. apiKey
    local payload = { 
        contents = {{
            parts = {{ text = prompt }}
        }}
    }
    local headers = { ["Content-Type"] = "application/json" }
    Http.post(url, cjson.encode(payload), headers, function(status, data)
        if status == 200 then
            local ok, decoded = pcall(cjson.decode, data)
            if ok and decoded and decoded.candidates and decoded.candidates[1] then
                local text = decoded.candidates[1].content and 
                             decoded.candidates[1].content.parts and 
                             decoded.candidates[1].content.parts[1] and 
                             decoded.candidates[1].content.parts[1].text
                if text then
                    callback(text, nil)
                else
                    callback(nil, "Invalid response from Gemini")
                end
            else
                callback(nil, "Failed to parse Gemini response")
            end
        else
            callback(nil, "Gemini Error: " .. status)
        end
    end)
end

function processWithAI(spokenText, callback)
    local apiKey = getGeminiApiKey()
    if not apiKey or apiKey == "" then
        callback(spokenText)
        return
    end
    local model = getGeminiModel()
    local emojiEnabled = isEmojiEnabled()
    local prompt
    if emojiEnabled then
        prompt = [[Process the following voice transcription:
1. Fix all spelling mistakes (Urdu and English both).
2. Add proper punctuation (. , ? !).
3. Keep natural language flow.
4. IMPORTANT: After each sentence, add ONE relevant emoji based on the sentence's sentiment.
5. Preserve language scripts strictly: English words must remain in Latin script, Urdu words in Urdu script. Do NOT transliterate.
6. Return only the final corrected text with emojis.

Raw text: ]] .. spokenText
    else
        prompt = [[Process the following voice transcription:
1. Fix all spelling mistakes (Urdu and English both).
2. Add proper punctuation (. , ? !).
3. Keep natural language flow.
4. Do NOT add any emojis.
5. Preserve language scripts strictly: English words must remain in Latin script, Urdu words in Urdu script. Do NOT transliterate.
6. Return only the corrected text.

Raw text: ]] .. spokenText
    end
    callGeminiAPI(apiKey, model, prompt, callback)
end

function showAISettingsDialog(mainDlg)
    local dlg = LuaDialog(service)
    dlg.setTitle("AI Engine Settings")
    dlg.setCancelable(true)
    local mainLayout = LinearLayout(service)
    mainLayout.setOrientation(1)
    mainLayout.setPadding(30, 20, 30, 20)
    
    local infoText = TextView(service)
    infoText.setText("Get API key from: https://aistudio.google.com/app/apikey")
    infoText.setTextSize(12)
    infoText.setTextColor(0xFFAAAAAA)
    infoText.setPadding(0, 0, 0, 20)
    mainLayout.addView(infoText)
    
    local keyLabel = TextView(service)
    keyLabel.setText("Gemini API Key:")
    keyLabel.setTextSize(14)
    keyLabel.setTextColor(0xFFFFFFFF)
    keyLabel.setPadding(0, 0, 0, 10)
    mainLayout.addView(keyLabel)
    
    local keyInput = EditText(service)
    keyInput.setHint("Enter Gemini API Key")
    local savedKey = getGeminiApiKey()
    if savedKey and savedKey ~= "" then keyInput.setText(savedKey) end
    keyInput.setTextSize(14)
    keyInput.setPadding(20, 15, 20, 15)
    keyInput.setBackgroundColor(0xFF222222)
    local keyParams = LinearLayout.LayoutParams(-1, -2)
    keyParams.setMargins(0, 0, 0, 15)
    keyInput.setLayoutParams(keyParams)
    mainLayout.addView(keyInput)
    
    local modelLabel = TextView(service)
    modelLabel.setText("Select Model:")
    modelLabel.setTextSize(14)
    modelLabel.setTextColor(0xFFFFFFFF)
    modelLabel.setPadding(0, 0, 0, 10)
    mainLayout.addView(modelLabel)
    
    local modelSpinner = Spinner(service)
    local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, GEMINI_MODELS)
    adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    modelSpinner.setAdapter(adapter)
    local currentModel = getGeminiModel()
    for i = 1, #GEMINI_MODELS do
        if GEMINI_MODELS[i] == currentModel then modelSpinner.setSelection(i - 1) break end
    end
    local spinnerParams = LinearLayout.LayoutParams(-1, -2)
    spinnerParams.setMargins(0, 0, 0, 15)
    modelSpinner.setLayoutParams(spinnerParams)
    mainLayout.addView(modelSpinner)

    -- API Typing Toggle Button
    local apiBtn = Button(service)
    local apiState = isApiTypingEnabled()
    apiBtn.setText(apiState and "API Typing: ON" or "API Typing: OFF")
    apiBtn.setTextSize(14)
    apiBtn.setBackgroundColor(0xFF333333)
    apiBtn.setPadding(0, 15, 0, 15)
    apiBtn.setLayoutParams(LinearLayout.LayoutParams(-1, -2))
    local apiBtnParams = apiBtn.getLayoutParams()
    apiBtnParams.setMargins(0, 0, 0, 15)
    apiBtn.setLayoutParams(apiBtnParams)
    apiBtn.setOnClickListener(function()
        local newState = not isApiTypingEnabled()
        setApiTypingEnabled(newState)
        apiBtn.setText(newState and "API Typing: ON" or "API Typing: OFF")
        service.speak("API Typing " .. (newState and "enabled" or "disabled"))
    end)
    mainLayout.addView(apiBtn)
    
    local buttonRow = LinearLayout(service)
    buttonRow.setOrientation(0)
    buttonRow.setPadding(0, 0, 0, 0)
    
    local testBtn = Button(service)
    testBtn.setText("TEST API KEY")
    testBtn.setTextSize(12)
    testBtn.setBackgroundColor(0xFFFF9800)
    testBtn.setPadding(0, 15, 0, 15)
    testBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    local testParams = testBtn.getLayoutParams()
    testParams.setMargins(0, 0, 5, 0)
    testBtn.setLayoutParams(testParams)
    
    local saveBtn = Button(service)
    saveBtn.setText("SAVE")
    saveBtn.setTextSize(12)
    saveBtn.setBackgroundColor(0xFF4CAF50)
    saveBtn.setPadding(0, 15, 0, 15)
    saveBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    local saveParams = saveBtn.getLayoutParams()
    saveParams.setMargins(5, 0, 5, 0)
    saveBtn.setLayoutParams(saveParams)
    
    local backBtn = Button(service)
    backBtn.setText("GO BACK")
    backBtn.setTextSize(12)
    backBtn.setBackgroundColor(0xFFF44336)
    backBtn.setPadding(0, 15, 0, 15)
    backBtn.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
    local backParams = backBtn.getLayoutParams()
    backParams.setMargins(5, 0, 0, 0)
    backBtn.setLayoutParams(backParams)
    
    buttonRow.addView(testBtn)
    buttonRow.addView(saveBtn)
    buttonRow.addView(backBtn)
    mainLayout.addView(buttonRow)
    
    testBtn.setOnClickListener(function()
        local testKey = keyInput.getText().toString()
        local testModel = GEMINI_MODELS[modelSpinner.getSelectedItemPosition() + 1]
        if not testKey or testKey == "" then
            service.speak("Enter API key first")
            return
        end
        testBtn.setText("Testing...")
        testBtn.setEnabled(false)
        testGeminiAPI(testKey, testModel, function(success, message)
            testBtn.setText("TEST API KEY")
            testBtn.setEnabled(true)
            if success then service.speak("Success: " .. message) else service.speak("Failed: " .. message) end
        end)
    end)
    
    saveBtn.setOnClickListener(function()
        local newKey = keyInput.getText().toString()
        local newModel = GEMINI_MODELS[modelSpinner.getSelectedItemPosition() + 1]
        if newKey and newKey ~= "" then saveGeminiApiKey(newKey) end
        if newModel then saveGeminiModel(newModel) end
        service.speak("Settings saved")
        dlg.dismiss()
        if mainDlg then mainDlg.show() end
    end)
    
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
  {name = "English (United States)", code = "en-US"},
  {name = "English (United Kingdom)", code = "en-GB"},
  {name = "English (India)", code = "en-IN"},
  {name = "English (Pakistan)", code = "en-PK"},
  {name = "Urdu", code = "ur-PK"},
  {name = "Hindi (India)", code = "hi-IN"},
  {name = "Punjabi (India)", code = "pa-IN"},
  {name = "Tamil (India)", code = "ta-IN"},
  {name = "Tamil (Sri Lanka)", code = "ta-LK"},
  {name = "Tamil (Singapore)", code = "ta-SG"},
  {name = "Tamil (Malaysia)", code = "ta-MY"},
  {name = "Bengali (Bangladesh)", code = "bn-BD"},
  {name = "Bengali (India)", code = "bn-IN"},
  {name = "Kannada (India)", code = "kn-IN"},
  {name = "Marathi (India)", code = "mr-IN"},
  {name = "Gujarati (India)", code = "gu-IN"},
  {name = "Sinhala (Sri Lanka)", code = "si-LK"},
  {name = "Telugu (India)", code = "te-IN"},
  {name = "Malayalam (India)", code = "ml-IN"},
  {name = "Nepali (Nepal)", code = "ne-NP"},
  {name = "Lao (Laos)", code = "lo-LA"},
  {name = "Thai (Thailand)", code = "th-TH"},
  {name = "Burmese (Myanmar)", code = "my-MM"},
  {name = "Khmer (Cambodia)", code = "km-KH"},
  {name = "Mandarin Chinese (Mainland China)", code = "zh-CN"},
  {name = "Mandarin Chinese (Taiwan)", code = "zh-TW"},
  {name = "Mandarin Chinese (Hong Kong)", code = "zh-HK"},
  {name = "Cantonese (Hong Kong)", code = "yue-Hant-HK"},
  {name = "Korean (South Korea)", code = "ko-KR"},
  {name = "Japanese (Japan)", code = "ja-JP"},
  {name = "Indonesian (Indonesia)", code = "id-ID"},
  {name = "Malay (Malaysia)", code = "ms-MY"},
  {name = "Javanese (Indonesia)", code = "jv-ID"},
  {name = "Sundanese (Indonesia)", code = "su-ID"},
  {name = "Filipino (Philippines)", code = "fil-PH"},
  {name = "Vietnamese (Vietnam)", code = "vi-VN"},
  {name = "Turkish (Turkey)", code = "tr-TR"},
  {name = "Azerbaijani (Azerbaijan)", code = "az-AZ"},
  {name = "Kazakh (Kazakhstan)", code = "kk-KZ"},
  {name = "Mongolian (Mongolia)", code = "mn-MN"},
  {name = "Georgian (Georgia)", code = "ka-GE"},
  {name = "Armenian (Armenia)", code = "hy-AM"},
  {name = "Uzbek (Uzbekistan)", code = "uz-UZ"},
  {name = "Hebrew (Israel)", code = "iw-IL"},
  {name = "Arabic (Israel)", code = "ar-IL"},
  {name = "Arabic (Jordan)", code = "ar-JO"},
  {name = "Arabic (UAE)", code = "ar-AE"},
  {name = "Arabic (Bahrain)", code = "ar-BH"},
  {name = "Arabic (Algeria)", code = "ar-DZ"},
  {name = "Arabic (Saudi Arabia)", code = "ar-SA"},
  {name = "Arabic (Kuwait)", code = "ar-KW"},
  {name = "Arabic (Morocco)", code = "ar-MA"},
  {name = "Arabic (Tunisia)", code = "ar-TN"},
  {name = "Arabic (Oman)", code = "ar-OM"},
  {name = "Arabic (Palestine)", code = "ar-PS"},
  {name = "Arabic (Egypt)", code = "ar-EG"},
  {name = "Arabic (Qatar)", code = "ar-QA"},
  {name = "Arabic (Lebanon)", code = "ar-LB"},
  {name = "Persian (Iran)", code = "fa-IR"},
}

table.sort(allLanguages, function(a,b) return a.name < b.name end)
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
          return
        end
      end
    end
  end
  changeTable = {}
end

function saveDictionary()
  ensureBackupFolder()
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

function clearAllDictionary()
  changeTable = {}
  saveDictionary()
end

function applyDictionaryReplacements(text)
  if not text or text == "" then return text end
  local result = text
  for wrong, correct in pairs(changeTable) do
    local pattern = escapePattern(wrong)
    result = result:gsub(pattern, correct)
  end
  return result
end

-- ============================================================
-- AI سے سیکھ کر ڈکشنری میں الفاظ شامل کرنے کا بہتر طریقہ
-- ============================================================
function learnFromAI(rawText, aiText)
  if not rawText or not aiText then return end

  -- الفاظ کو صاف کرنے کا مددگار فنکشن
  local function clean(w)
    -- شروع اور آخر سے رموز، خالی جگہیں، اور عام اردو نشانات ہٹائیں
    return (w:gsub("^[%p%s،۔؟!]+", ""):gsub("[%p%s،۔؟!]+$", ""))
  end

  local rawWords = {}
  for w in rawText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" then table.insert(rawWords, cw) end
  end

  local aiWords = {}
  for w in aiText:gmatch("%S+") do
    local cw = clean(w)
    if cw ~= "" then table.insert(aiWords, cw) end
  end

  -- اگر الفاظ کی تعداد برابر ہو تو ایک ایک کرکے موازنہ کریں
  if #rawWords == #aiWords then
    for i = 1, #rawWords do
      local rw = rawWords[i]
      local aw = aiWords[i]
      if rw ~= aw then
        addToDictionary(rw, aw)
      end
    end
  else
    -- اگر تعداد برابر نہ ہو تو ہر خام لفظ کے لیے AI الفاظ میں اس کا مماثل ڈھونڈیں
    for _, rw in ipairs(rawWords) do
      local found = false
      -- پہلے بالکل مماثل لفظ ڈھونڈیں
      for _, aw in ipairs(aiWords) do
        if rw == aw then found = true break end
      end
      -- اگر نہ ملے تو وہ لفظ تبدیل ہوا ہے، قریب ترین ڈھونڈیں
      if not found then
        -- خاص طور پر الف / الف مد کی صورت
        if rw:find("^[اآ]") then
          local base = rw:sub(2)
          local altStart = (rw:find("^ا") and "آ") or "ا"
          local altWord = altStart .. base
          for _, aw in ipairs(aiWords) do
            if aw == altWord then
              addToDictionary(rw, altWord)
              break
            end
          end
        else
          -- عمومی تبدیلی: اگر AI نے کوئی مختلف لفظ دیا اور خام لفظ AI الفاظ میں سے کسی سے بھی میل نہیں کھاتا،
          -- تو پہلا ایسا AI لفظ استعمال کریں جس کی لمبائی قریب ہو (احتیاط کے ساتھ)
          for _, aw in ipairs(aiWords) do
            if aw ~= rw and #aw >= #rw - 1 and #aw <= #rw + 2 then
              addToDictionary(rw, aw)
              break
            end
          end
        end
      end
    end
  end
end

-- ============================================================
-- ڈکشنری ڈائیلاگ
-- ============================================================
function showDictionaryDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Add to Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "20dp";
    { EditText; id = "wrongWord"; hint = "Wrong word"; textSize = "16sp"; layout_width = "fill"; layout_marginBottom = "15dp"; };
    { EditText; id = "correctWord"; hint = "Correct word"; textSize = "16sp"; layout_width = "fill"; layout_marginBottom = "15dp"; };
    { Button; text = "Add to Dictionary"; textSize = "16sp"; layout_width = "fill"; onClick = function()
        local wrong = wrongWord.getText().toString()
        local correct = correctWord.getText().toString()
        if wrong ~= "" and correct ~= "" then
          addToDictionary(wrong, correct)
          service.speak("Added: " .. wrong .. " → " .. correct)
          dlg.dismiss()
        else
          service.speak("Both fields required")
        end
      end;
    };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

function showDictionaryList()
  loadDictionary()
  if next(changeTable) == nil then
    service.speak("Dictionary is empty")
    return
  end
  local itemsList = {}
  for wrong, correct in pairs(changeTable) do
    local display = "Wrong: " .. wrong .. ", Correct: " .. correct
    table.insert(itemsList, {wrong = wrong, correct = correct, display = display})
  end
  local displayItems = {}
  for _, item in ipairs(itemsList) do table.insert(displayItems, item.display) end
  local dlg = LuaDialog(service)
  dlg.setTitle("Dictionary List (Long press to delete)")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { Button; text = "Empty Dictionary"; textSize = "14sp"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function()
        local confirmDlg = LuaDialog(service)
        confirmDlg.setTitle("Clear Dictionary")
        confirmDlg.setMessage("Are you sure you want to delete ALL dictionary entries?")
        confirmDlg.setButton("Yes", function()
          clearAllDictionary()
          service.speak("Dictionary cleared")
          confirmDlg.dismiss()
          dlg.dismiss()
          showDictionaryList()
        end)
        confirmDlg.setButton2("No", function() confirmDlg.dismiss() end)
        confirmDlg.show()
      end;
    };
    { ListView; id = "list"; layout_width = "fill"; layout_height = "400dp"; };
    { Button; text = "Close"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, displayItems)
  list.setAdapter(adapter)
  list.setOnItemLongClickListener(function(parent, v, position, id)
    local selectedDisplay = displayItems[position + 1]
    local wrongWord = nil
    for _, item in ipairs(itemsList) do
      if item.display == selectedDisplay then wrongWord = item.wrong break end
    end
    if wrongWord then
      local confirmDlg = LuaDialog(service)
      confirmDlg.setTitle("Delete Word")
      confirmDlg.setMessage("Delete " .. wrongWord .. " from dictionary?")
      confirmDlg.setButton("Yes", function()
        deleteFromDictionary(wrongWord)
        service.speak("Deleted: " .. wrongWord)
        confirmDlg.dismiss()
        dlg.dismiss()
        showDictionaryList()
      end)
      confirmDlg.setButton2("No", function() confirmDlg.dismiss() end)
      confirmDlg.show()
    end
    return true
  end)
  dlg.setView(view)
  dlg.show()
end

function showDigitalDictionary()
  local dlg = LuaDialog(service)
  dlg.setTitle("Digital Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "25dp";
    { TextView; text = "Manage your custom word replacements"; textSize = "14sp"; textColor = "#666666"; layout_marginBottom = "20dp"; gravity = "center"; };
    { Button; text = "Add New Entry"; textSize = "16sp"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        dlg.dismiss()
        showDictionaryDialog()
      end;
    };
    { Button; text = "View / Edit Dictionary"; textSize = "16sp"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        dlg.dismiss()
        showDictionaryList()
      end;
    };
    { Button; text = "Clear All Dictionary"; textSize = "16sp"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function()
        local confirmDlg = LuaDialog(service)
        confirmDlg.setTitle("Clear All Entries")
        confirmDlg.setMessage("Are you sure you want to remove EVERY word from the dictionary?")
        confirmDlg.setButton("Yes", function()
          clearAllDictionary()
          service.speak("All dictionary entries cleared")
          confirmDlg.dismiss()
          dlg.dismiss()
        end)
        confirmDlg.setButton2("No", function() confirmDlg.dismiss() end)
        confirmDlg.show()
      end;
    };
    { View; layout_width = "fill"; layout_height = "1dp"; backgroundColor = "#CCCCCC"; layout_marginTop = "10dp"; layout_marginBottom = "15dp"; };
    { Button; text = "Back to Main Menu"; textSize = "16sp"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
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
          primaryLangCode = data.primary or "en-US"
          secondaryLangCode = data.secondary or "ur-PK"
          favouriteIndices = data.favourites or {}
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.autoCorrectUrdu = true  -- ہمیشہ فعال، لیکن اب استعمال نہیں ہوگا
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
    autoCorrectUrdu = settings.autoCorrectUrdu
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

-- پنکچویشن سیٹنگز ڈائیلاگ (آٹو کریکٹ کے بغیر)
function showPunctuationSettingsDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Punctuation Settings")
  local currentPunct = settings.punctuation
  local punctOptions = {"New line", "Dot only", "Space only", "None"}
  local punctValues = {"newline", "dot_only", "space_only", "none"}
  local selectedIndex = 0
  for i, v in ipairs(punctValues) do if v == currentPunct then selectedIndex = i break end end
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "20dp";
    { TextView; text = "End of sentence:"; textSize = "16sp"; layout_marginBottom = "10dp"; };
    { Spinner; id = "punctSpinner"; layout_width = "fill"; layout_marginBottom = "20dp"; };
    { Button; text = "Save Settings"; layout_width = "fill"; onClick = function()
        settings.punctuation = punctValues[punctSpinner.getSelectedItemPosition() + 1]
        saveAllSettings()
        service.speak("Settings saved")
        dlg.dismiss()
      end;
    };
  }
  local view = loadlayout(layout)
  local adapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, punctOptions)
  adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
  punctSpinner.setAdapter(adapter)
  punctSpinner.setSelection(selectedIndex - 1)
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- BACKUP / RESTORE
-- ============================================================
function backupDictionary()
  ensureBackupFolder()
  if saveDictionary() then
    if copyFile(dictFile, dictBackupFile) then
      service.speak("Dictionary backup completed.")
    else
      service.speak("Dictionary backup failed.")
    end
  end
end

function backupSettings()
  ensureBackupFolder()
  if saveAllSettings() then
    if copyFile(settingsFile, settingsBackupFile) then
      service.speak("Settings backup completed.")
    else
      service.speak("Settings backup failed.")
    end
  end
end

function getBackupTextFiles()
  local folder = File(backupFolder)
  if not folder.exists() then return {} end
  local files = {}
  local list = folder.listFiles()
  if list == nil then return {} end
  for i = 0, #list - 1 do
    local f = list[i]
    if f.isFile() and f.getName():match("%.txt$") then
      if f.getName() ~= "dictionary.txt" and f.getName() ~= "digital_typer_settings.txt" then
        table.insert(files, {path = f.getPath(), name = f.getName(), size = f.length()})
      end
    end
  end
  return files
end

function isValidDictionaryFile(filePath)
  local f = io.open(filePath, "r")
  if not f then return false end
  local content = f:read("*all")
  f:close()
  if not content or content == "" then return false end
  content = content:gsub("^\239\187\191", "")
  local func = loadstring("return " .. content)
  if not func then func = loadstring(content) end
  if not func then return false end
  local ok, dict = pcall(func)
  return ok and type(dict) == "table"
end

function isValidSettingsFile(filePath)
  local f = io.open(filePath, "r")
  if not f then return false end
  local content = f:read("*all")
  f:close()
  if not content or content == "" then return false end
  content = content:gsub("^\239\187\191", "")
  local func = loadstring(content)
  if not func then func = loadstring(content) end
  if not func then return false end
  local ok, data = pcall(func)
  return ok and type(data) == "table"
end

function restoreDictionary()
  local files = getBackupTextFiles()
  local dictFiles = {}
  for _, f in ipairs(files) do if isValidDictionaryFile(f.path) then table.insert(dictFiles, f) end end
  if #dictFiles == 0 then service.speak("No valid backup found") return end
  local dlg = LuaDialog(service)
  dlg.setTitle("Restore Dictionary")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { ListView; id = "fileList"; layout_width = "fill"; layout_height = "400dp"; };
    { Button; text = "Cancel"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  local displayNames = {}
  for _, f in ipairs(dictFiles) do table.insert(displayNames, f.name) end
  fileList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, displayNames))
  fileList.onItemClick = function(l, v, p, i)
    local selected = dictFiles[p+1]
    if copyFile(selected.path, dictFile) then
      loadDictionary()
      service.speak("Dictionary restored.")
      dlg.dismiss()
    end
  end
  dlg.setView(view)
  dlg.show()
end

function restoreSettings()
  local files = getBackupTextFiles()
  local settingsFiles = {}
  for _, f in ipairs(files) do if isValidSettingsFile(f.path) then table.insert(settingsFiles, f) end end
  if #settingsFiles == 0 then service.speak("No valid settings backup found") return end
  local dlg = LuaDialog(service)
  dlg.setTitle("Restore Settings")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { ListView; id = "fileList"; layout_width = "fill"; layout_height = "400dp"; };
    { Button; text = "Cancel"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  local displayNames = {}
  for _, f in ipairs(settingsFiles) do table.insert(displayNames, f.name) end
  fileList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, displayNames))
  fileList.onItemClick = function(l, v, p, i)
    local selected = settingsFiles[p+1]
    if copyFile(selected.path, settingsFile) then
      loadAllSettings()
      service.speak("Settings restored.")
      dlg.dismiss()
    end
  end
  dlg.setView(view)
  dlg.show()
end

function showDeleteFilePicker()
  local files = getBackupTextFiles()
  if #files == 0 then service.speak("No files to delete") return end
  local dlg = LuaDialog(service)
  dlg.setTitle("Delete Backup File")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { ListView; id = "fileList"; layout_width = "fill"; layout_height = "400dp"; };
    { Button; text = "Cancel"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layout)
  local displayNames = {}
  for _, f in ipairs(files) do table.insert(displayNames, f.name) end
  fileList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, displayNames))
  fileList.onItemClick = function(l, v, p, i)
    local selected = files[p+1]
    File(selected.path).delete()
    service.speak("File deleted.")
    dlg.dismiss()
  end
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- LANGUAGE PICKER AND FAVOURITES
-- ============================================================
function getLanguageNameFromCode(code)
  if not languageCodes then return "Unknown" end
  for i, c in ipairs(languageCodes) do if c == code then return languageItems[i] end end
  return "Unknown"
end

function showLanguagePicker(callback, title)
  local dlg = LuaDialog(service)
  dlg.setTitle(title or "Select Language")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { EditText; id = "searchBox"; hint = "Search language..."; textSize = "14sp"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { ListView; id = "langList"; layout_width = "fill"; layout_height = "350dp"; };
  }
  local view = loadlayout(layout)
  local fullAdapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, languageItems)
  langList.setAdapter(fullAdapter)
  searchBox.addTextChangedListener({
    onTextChanged = function(s)
      local query = tostring(s):lower()
      local filtered = {}
      for i, item in ipairs(languageItems) do if item:lower():find(query) then table.insert(filtered, item) end end
      langList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, filtered))
    end
  })
  langList.onItemClick = function(l, v, p, i)
    local selectedItem = langList.getAdapter().getItem(p)
    for idx, item in ipairs(languageItems) do
      if item == selectedItem then callback(languageCodes[idx], selectedItem) dlg.dismiss() break end
    end
  end
  langList.setOnItemLongClickListener(function(parent, v, position, id)
    local selectedItem = langList.getAdapter().getItem(position)
    for idx, item in ipairs(languageItems) do
      if item == selectedItem then
        local already = false
        for _, fidx in ipairs(favouriteIndices) do if fidx == idx then already = true break end end
        if not already then
          table.insert(favouriteIndices, idx)
          saveAllSettings()
          service.speak("Added to favourites")
        end
        return true
      end
    end
    return false
  end)
  dlg.setView(view)
  dlg.show()
end

function showFavouritesDialog()
  if #favouriteIndices == 0 then service.speak("No favourites") return end
  local favItems = {}
  for _, idx in ipairs(favouriteIndices) do table.insert(favItems, languageItems[idx]) end
  local dlg = LuaDialog(service)
  dlg.setTitle("★ Favourite Languages ★")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "10dp";
    { ListView; id = "favList"; layout_width = "fill"; layout_height = "400dp"; };
    { Button; text = "Clear All"; layout_width = "fill"; onClick = function() favouriteIndices = {} saveAllSettings() dlg.dismiss() end; };
  }
  favList.setAdapter(ArrayAdapter(service, android.R.layout.simple_list_item_1, favItems))
  favList.onItemClick = function(l,v,p,i)
    primaryLangCode = languageCodes[favouriteIndices[p+1]]
    saveAllSettings()
    service.speak("Primary set.")
    dlg.dismiss()
  end
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- Voice typing (AI integrated)
-- ============================================================
function startVoiceTyping(langCode)
  local speechRec = SpeechRecognizer.createSpeechRecognizer(service.getApplicationContext())
  local listener = RecognitionListener {
    onResults = function(results)
      local res = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if res and res.size() > 0 then
        local rawText = res.get(0)
        local function fallback()
          local finalText = rawText
          finalText = applyDictionaryReplacements(finalText)
          finalText = applyEndPunctuation(finalText)
          service.insertText(service.getEditText(), finalText)
          service.speak(finalText)
        end
        
        if isApiTypingEnabled() and getGeminiApiKey() ~= "" then
          processWithAI(rawText, function(aiText)
            if aiText then
              -- AI سے سیکھ کر ڈکشنری میں درستگیاں شامل کریں
              learnFromAI(rawText, aiText)
              local finalText = applyDictionaryReplacements(aiText)
              finalText = applyEndPunctuation(finalText)
              service.insertText(service.getEditText(), finalText)
              service.speak(finalText)
            else
              fallback()
            end
          end)
        else
          fallback()
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
-- WhatsApp
-- ============================================================
function openWhatsApp()
  local url = "https://wa.me/923477583735?text=Hello"
  local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
  intent.setPackage("com.whatsapp")
  intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
  service.startActivity(intent)
end

-- ============================================================
-- MAIN MENU
-- ============================================================
function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("digital typer")
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "toggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Set Primary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) primaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Set Secondary Language"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showLanguagePicker(function(c, n) secondaryLangCode = c saveAllSettings() end) end; };
    { Button; text = "Favourite Languages"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showFavouritesDialog() end; };
    { Button; text = "Digital Dictionary"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showDigitalDictionary() end; };
    { Button; text = "Punctuation Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showPunctuationSettingsDialog() end; };
    { Button; text = "AI Engine Settings"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() dlg.dismiss() showAISettingsDialog(dlg) end; };
    { Button; text = "Backup / Restore"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function() showBackupRestoreDialog() end; };
    { Button; text = "About / Contact"; layout_width = "fill"; layout_marginBottom = "10dp"; onClick = function()
        local abt = LuaDialog(service)
        abt.setTitle("About")
        abt.setMessage("digital typer\nCreated by A Brothers")
        abt.setButton("WhatsApp", function() openWhatsApp() end)
        abt.show()
      end;
    };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  local view = loadlayout(layoutTable)
  local function updateUI() toggleBtn.setText(settings.showLangDialog and "Show dialog: ON" or "Show dialog: OFF") end
  toggleBtn.onClick = function() settings.showLangDialog = not settings.showLangDialog saveAllSettings() updateUI() end
  updateUI()
  dlg.setView(view)
  dlg.show()
end

function showBackupRestoreDialog()
  local dlg = LuaDialog(service)
  dlg.setTitle("Backup & Restore")
  local layout = {
    LinearLayout; orientation = "vertical"; padding = "20dp";
    { Button; text = "Backup Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupDictionary() end; };
    { Button; text = "Backup Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() backupSettings() end; };
    { Button; text = "Restore Dictionary"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() restoreDictionary() end; };
    { Button; text = "Restore Settings"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() restoreSettings() end; };
    { Button; text = "Delete Files"; layout_width = "fill"; onClick = function() showDeleteFilePicker() end; };
  }
  dlg.setView(loadlayout(layout))
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