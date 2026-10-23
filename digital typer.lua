require "import"
import "android.widget.*"
import "android.content.Intent"
import "android.speech.SpeechRecognizer"
import "android.speech.RecognitionListener"
import "android.speech.RecognizerIntent"
import "android.content.Context"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "android.os.Environment"
import "com.androlua.Http"
import "cjson"

-- ============================================================
-- فائل راستے
-- ============================================================
local backupFolder = os.getenv("EXTERNAL_STORAGE") .. "/解说/Plugins/digital typer/backup"
local dictFile = backupFolder .. "/dictionary.txt"
local settingsFile = backupFolder .. "/digital_typer_settings.txt"
local offline100kDictFile = backupFolder .. "/alif_madda_100k.txt"

local changeTable = {}
local offlineAlifMaddaTable = {}
local MAX_DICT_LIMIT = 100000 -- 1 لاکھ الفاظ کی لمٹ سیٹ کر دی گئی ہے

-- سیٹنگز
local settings = { 
    punctuation = "newline", 
    showLangDialog = true, 
    autoCorrectUrdu = false,
    offlineModeEnabled = false -- نیا آپشن: Use without internet (By default OFF)
}
local primaryLangCode = "ur-PK"
local secondaryLangCode = "en-PK"

function ensureBackupFolder()
  local folder = File(backupFolder)
  if not folder.exists() then folder.mkdirs() end
end

-- ============================================================
-- 1 لاکھ الفاظ کی سپورٹ کے ساتھ آف لائن بیس ڈکشنری
-- ============================================================
function createBaseOfflineDictionary()
    ensureBackupFolder()
    -- یہاں وہ الفاظ ہیں جو گوگل سپیچ غلط سنتا ہے اور انہیں الف مدہ کی ضرورت ہوتی ہے
    local baseWords = {
        ["اپ"] = "آپ", ["اج"] = "آج", ["انا"] = "آنا", ["ادمی"] = "آدمی",
        ["اسمان"] = "آسمان", ["اگ"] = "آگ", ["اٹا"] = "آٹا", ["استان"] = "آستان",
        ["اہ"] = "آہ", ["ارام"] = "آرام", ["اباد"] = "آباد", ["افت"] = "آفت",
        ["انسو"] = "آنسو", ["اخری"] = "آخری", ["واز"] = "آواز", ["انکھیں"] = "آنکھیں",
        ["اداب"] = "آداب", ["اسان"] = "آسان", ["آم"] = "آم", ["ایت"] = "آیت",
        ["ارہی"] = "آرہی", ["ارہا"] = "آرہا", ["ارہے"] = "آرہے", ["ارھے"] = "آرہے",
        ["ا رہی"] = "آ رہی", ["ا رہا"] = "آ رہا", ["ا رہے"] = "آ رہے",
        ["ازاد"] = "آزاد", ["ازادی"] = "آزادی", ["اسپاس"] = "آس پاس",
        ["ایندہ"] = "آئندہ", ["اغاز"] = "آغاز", ["ابادی"] = "آبادی", 
        ["الو"] = "آلو", ["امدن"] = "آمدن", ["امدی"] = "آمدی", 
        ["اڑو"] = "آڑو", ["اری"] = "آری", ["اہستہ"] = "آہستہ", 
        ["اخر"] = "آخر", ["ادھا"] = "آدھا", ["ادھے"] = "آدھے", ["ادھی"] = "آدھی",
        ["اشنا"] = "آشنا", ["اغوش"] = "آغوش", ["الہ"] = "آلہ", 
        ["اموز"] = "آموز", ["انچ"] = "آنچ", ["اندھی"] = "آندھی", 
        ["انگن"] = "آنگن", ["اہٹ"] = "آہٹ", ["ائینہ"] = "آئینہ", ["اخرکار"] = "آخرکار",
        ["ابشار"] = "آبشار", ["ابرو"] = "آبرو", ["ازمانا"] = "آزمانا", ["ازمائش"] = "آزمائش",
        ["اسرہ"] = "آسرہ", ["اسودہ"] = "آسودہ", ["اغیار"] = "آغیار", ["الودہ"] = "آلودہ",
        ["امنے"] = "آمنے", ["اوارہ"] = "آوارہ", ["اہن"] = "آہن", ["ایات"] = "آیات",
        ["امادہ"] = "آمادہ", ["اراستہ"] = "آراستہ", ["ازردہ"] = "آزردہ", ["اسیہ"] = "آسیہ"
    }
    -- نوٹ: یہ سمارٹ انجن "اپنے", "اپنا", "امید", "اچھا", "اس" کو نہیں چھیڑے گا 
    -- کیونکہ وہ الفاظ کی مکمل باؤنڈری سے میچ نہیں کرتے۔ 
    
    local f = io.open(offline100kDictFile, "w")
    if f then
        for wrong, correct in pairs(baseWords) do
            f:write(wrong .. "=" .. correct .. "\n")
        end
        f:close()
    end
    return baseWords
end

function loadOffline100kDictionary()
    local f = io.open(offline100kDictFile, "r")
    offlineAlifMaddaTable = {}
    local count = 0
    
    if f then
        for line in f:lines() do
            if count >= MAX_DICT_LIMIT then break end
            local wrong, correct = line:match("^([^=]+)=([^=]+)$")
            if wrong and correct then
                offlineAlifMaddaTable[wrong:match("^%s*(.-)%s*$")] = correct:match("^%s*(.-)%s*$")
                count = count + 1
            end
        end
        f:close()
    else
        offlineAlifMaddaTable = createBaseOfflineDictionary()
    end
end

-- ============================================================
-- SMART CONTEXTUAL ENGINE (آف لائن پروسیسنگ)
-- ============================================================
function processOfflineUrduText(rawText)
    -- اگر آف لائن پروسیسنگ آپشن OFF ہے، تو جو بولا گیا ہے وہی واپس کر دو
    if not settings.offlineModeEnabled then 
        return rawText 
    end
    
    if not rawText or rawText == "" then return rawText end
    
    local result = ""
    local lastPos = 1
    
    -- یہ لوپ ہر لفظ کو الگ کرتا ہے۔ 
    -- اس کا فائدہ یہ ہے کہ جب آپ "اپنا" بولیں گے، تو یہ اسے ایک مکمل لفظ مانے گا اور 
    -- "اپ" کی ڈکشنری اس پر اپلائی نہیں ہوگی۔ اس طرح الف اور الف مدہ میں فرق رہے گا۔
    for word in rawText:gmatch("[^%s%p۔،؟]+") do
        local startPos, endPos = rawText:find(word, lastPos, true)
        if startPos then
            result = result .. rawText:sub(lastPos, startPos - 1)
            
            if offlineAlifMaddaTable[word] then
                result = result .. offlineAlifMaddaTable[word]
            elseif changeTable[word] then
                result = result .. changeTable[word]
            else
                result = result .. word
            end
            
            lastPos = endPos + 1
        end
    end
    result = result .. rawText:sub(lastPos)
    return result
end

-- ============================================================
-- سیٹنگز سیو اور لوڈ کرنے کا نظام
-- ============================================================
function loadAllSettings()
  local f = io.open(settingsFile, "r")
  if f then
    local content = f:read("*all")
    f:close()
    if content and content ~= "" then
      local func = loadstring(content)
      if func then
        local data = func()
        if type(data) == "table" then
          primaryLangCode = data.primary or "ur-PK"
          secondaryLangCode = data.secondary or "en-PK"
          settings.punctuation = data.punctuation or "newline"
          settings.showLangDialog = (data.showLangDialog == nil) and true or data.showLangDialog
          settings.offlineModeEnabled = data.offlineModeEnabled or false
          return true
        end
      end
    end
  end
end

function saveAllSettings()
  ensureBackupFolder()
  local f = io.open(settingsFile, "w")
  if f then
      local content = string.format(
          "return { primary = %q, secondary = %q, punctuation = %q, showLangDialog = %s, offlineModeEnabled = %s }",
          primaryLangCode, secondaryLangCode, settings.punctuation, 
          tostring(settings.showLangDialog), tostring(settings.offlineModeEnabled)
      )
      f:write(content)
      f:close()
  end
end

function applyEndPunctuation(text)
  if settings.punctuation == "none" then return text
  elseif settings.punctuation == "dot_only" then return text:match("[.!?]$") and text or text .. "."
  elseif settings.punctuation == "space_only" then return text:match("%s$") and text or text .. " "
  elseif settings.punctuation == "newline" then return text:match("\n$") and text or text .. "\n" end
  return text
end

-- ============================================================
-- وائس ٹائپنگ لاجک
-- ============================================================
function startVoiceTyping(langCode)
  local speechRec = SpeechRecognizer.createSpeechRecognizer(service.getApplicationContext())
  local listener = RecognitionListener {
    onResults = function(results)
      local res = results.getParcelableArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
      if res and res.size() > 0 then
        local rawText = res.get(0)
        
        -- سمارٹ آف لائن انجن کال ہو رہا ہے (یہ سیٹنگ کے لحاظ سے فیصلہ کرے گا)
        local finalText = processOfflineUrduText(rawText)
        finalText = applyEndPunctuation(finalText)
        
        service.insertText(service.getEditText(), finalText)
        service.speak(finalText)
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
    { Button; text = "Primary (Urdu)"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(primaryLangCode) end; };
    { Button; text = "Secondary (English)"; layout_width = "fill"; layout_marginBottom = "15dp"; onClick = function() dlg.dismiss(); startVoiceTyping(secondaryLangCode) end; };
    { Button; text = "Settings"; layout_width = "fill"; onClick = function() dlg.dismiss(); showMainMenu() end; };
  }
  dlg.setView(loadlayout(layout))
  dlg.show()
end

-- ============================================================
-- مین مینو (ڈائیلاگ اور آف لائن موڈ ٹوگل کے ساتھ)
-- ============================================================
function showMainMenu()
  local dlg = LuaDialog()
  dlg.setTitle("Digital Typer Settings")
  local views = {}
  
  local layoutTable = {
    LinearLayout; orientation = "vertical"; padding = "30dp";
    { Button; id = "offlineToggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; id = "dialogToggleBtn"; layout_width = "fill"; layout_marginBottom = "10dp"; };
    { Button; text = "Exit"; layout_width = "fill"; onClick = function() dlg.dismiss() end; };
  }
  
  local view = loadlayout(layoutTable, views)
  
  local function updateUI() 
      views.dialogToggleBtn.setText(settings.showLangDialog and "Show Language Dialog: ON" or "Show Language Dialog: OFF") 
      views.offlineToggleBtn.setText(settings.offlineModeEnabled and "Use Without Internet (Auto-Correct): ON" or "Use Without Internet (Auto-Correct): OFF") 
      
      -- آف لائن بٹن کا رنگ تبدیل کریں تاکہ واضح ہو
      if settings.offlineModeEnabled then
          views.offlineToggleBtn.setBackgroundColor(0xFF4CAF50) -- Green
      else
          views.offlineToggleBtn.setBackgroundColor(0xFFF44336) -- Red
      end
  end
  
  views.dialogToggleBtn.onClick = function() 
      settings.showLangDialog = not settings.showLangDialog 
      saveAllSettings() 
      updateUI() 
  end
  
  views.offlineToggleBtn.onClick = function() 
      settings.offlineModeEnabled = not settings.offlineModeEnabled 
      saveAllSettings() 
      updateUI() 
      
      if settings.offlineModeEnabled then
          service.speak("Offline Auto Correct Enabled")
      else
          service.speak("Offline Auto Correct Disabled. Normal typing active.")
      end
  end
  
  updateUI()
  dlg.setView(view)
  dlg.show()
end

-- ============================================================
-- Entry Point
-- ============================================================
ensureBackupFolder()
loadAllSettings()
loadOffline100kDictionary() -- 1 لاکھ کی لمٹ والی فائل میموری میں لوڈ ہو رہی ہے

if service.getEditText() then
  if settings.showLangDialog then 
      showTypingDialog() 
  else 
      startVoiceTyping(primaryLangCode) 
  end
else
  showMainMenu()
end
