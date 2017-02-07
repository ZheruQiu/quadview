
require("wx")

VERSION = "0.5m"

-----------------------------------------------------------
-- Generate a unique new wxWindowID
-----------------------------------------------------------

local COUNTER = wx.wxID_HIGHEST + 1

local function NewID()
    COUNTER = COUNTER + 1
    return COUNTER
end

ID = { }

-----------------------------------------------------------
-- Create main frame and bitmap controls
-----------------------------------------------------------

sep = package.config:sub(1,1) -- path separator

mainpath = wx.wxGetCwd()
datapath = os.getenv("APPDATA") .. sep .. "QuadView"
cfgname = datapath .. sep .. "quadview.ini"
runname = datapath .. sep .. "running"
predefine_preamble = datapath .. sep .. "predefine_preamble.tex"
latexerr=""

if not wx.wxFileName.DirExists(datapath) and not wx.wxFileName.Mkdir(datapath) then
    wx.wxMessageBox("Failed to create main folder!", "Error")
    return
end

if not wx.wxFileName.FileExists(cfgname) then
    wx.wxMessageBox("Make sure you have installed preview package\n"
        .. "into your miktex or texlive distribution!", "Requirement")
end

local file = wx.wxFile()
file:Create(runname, true)
file:Close()

frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "QuadView" .. " " .. VERSION, wx.wxPoint(656,132),
                   wx.wxSize(350, 250), wx.wxDEFAULT_FRAME_STYLE+wx.wxSTAY_ON_TOP)

image = wx.wxImage()
bitmap = wx.wxBitmap()
preview = wx.wxStaticBitmap(frame, wx.wxID_ANY)

statusbar = frame:CreateStatusBar()
frame:SetStatusText("Ready")

frame:Connect(wx.wxEVT_CLOSE_WINDOW, function(event)
    image:delete()
    bitmap:delete()
    if not wx.wxRemoveFile(runname) then
        wx.wxMessageBox("Unable to delete file!", "Error", wx.wxOK + wx.wxCENTRE, frame)
    end
    SavePosition()
    SaveSettings()
    event:Skip()
end)

-----------------------------------------------------------
-- Save and restore configurations
-----------------------------------------------------------

function GetConfig()
    local config = wx.wxFileConfig("QuadView", "", cfgname)
    if config then
        config:SetRecordDefaults()
    else
        --print("Failed to load config file!")
    end
    return config
end

function SavePosition()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/MainFrame")

    local s    = 0
    local w, h = frame:GetSizeWH()
    local x, y = frame:GetPositionXY()

    if frame:IsMaximized() then
        s = 1
    elseif frame:IsIconized() then
        s = 2
    end

    config:Write("s", s)

    if s == 0 then
        config:Write("x", x)
        config:Write("y", y)
        config:Write("w", w)
        config:Write("h", h)
    end

    config:delete() -- always delete the config
end

function RestorePosition()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/MainFrame")

    local _, s = config:Read("s", -1)
    local _, x = config:Read("x", 0)
    local _, y = config:Read("y", 0)
    local _, w = config:Read("w", 0)
    local _, h = config:Read("h", 0)

    if (s ~= -1) and (s ~= 1) and (s ~= 2) then
        local clientX, clientY, clientWidth, clientHeight
        clientX, clientY, clientWidth, clientHeight = wx.wxClientDisplayRect()

        if x < clientX then x = clientX end
        if y < clientY then y = clientY end

        if w > clientWidth  then w = clientWidth end
        if h > clientHeight then h = clientHeight end

        frame:SetSize(x, y, w, h)
    elseif s == 1 then
        frame:Maximize(true)
    end

    config:delete() -- always delete the config
end

RestorePosition()

function SaveSettings()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/Settings")
    config:Write("engine", engine)
    config:Write("resolution", resolution)
    config:Write("heightlevel",heightlevel)

    config:delete() -- always delete the config
end

function RestoreSettings()
    local config = GetConfig()
    if not config then return end

    config:SetPath("/Settings")
    _, engine = config:Read("engine", "xelatex")
    _, resolution = config:Read("resolution", 450)
    _, heightlevel = config:Read("heightlevel", "VM")

    config:delete() -- always delete the config
end

RestoreSettings()

-----------------------------------------------------------
-- Resize the preview image
-----------------------------------------------------------

ID.TIMER_RESIZE = NewID()
local sizeTimer = wx.wxTimer(frame, ID.TIMER_RESIZE)


frame:Connect(wx.wxEVT_SIZE, function(event)
    sizeTimer:Start(100, true)
    --print("ts")
    event:Skip()
end)

function TimerResize()
	--print("trs")
    ResizeControl()
    sizeTimer:Stop()
end

frame:Connect(ID.TIMER_RESIZE, wx.wxEVT_TIMER, TimerResize)


function ResizeControl()
	--print("here")
    local size = frame:GetSize()
    local w, h = size:GetWidth(), size:GetHeight()
    --print("w"..tostring(w).."h"..tostring(h))
    size = frame:GetClientSize()
    local cw, ch = size:GetWidth(), size:GetHeight()
    --print("cw"..tostring(cw).."ch"..tostring(ch))
    local iw, ih = image:GetWidth(), image:GetHeight()
	--print("iw"..tostring(iw).."ih"..tostring(ih))
    if iw == 0 then iw = 320 end
    if ih == 0 then ih = 240 end
    local nh =  math.floor(cw * ih / iw)
    --print("w" .. tostring(w) .. "h" .. tostring(h).."cw"..tostring(cw).."ch"..tostring(ch).."iw"..tostring(iw).."ih"..tostring(ih).."nh"..tostring(nh))
    bitmap = wx.wxBitmap(image:Scale(cw, nh, wx.wxIMAGE_QUALITY_HIGH))
    preview:SetBitmap(bitmap)
    preview:SetSize(0, 0, cw, ch)
    if nh - ch > 2 or ch - nh > 2 then
    	--print("Size set to " .. tostring(w) .. " " .. tostring(h + nh - ch))
        frame:SetSize(w, h + nh - ch)
    end
    frame:Refresh()
end

-----------------------------------------------------------
-- Execute commands asynchronously
-----------------------------------------------------------

local proc, streamIn, streamErr, streamOut
local isRunning = false

ID.TIMER_EXECUTION = NewID()
local execTimer = wx.wxTimer(frame, ID.TIMER_EXECUTION)

function ReadStream()
    if streamIn and streamIn:CanRead() then
        local str = streamIn:Read(4096)
        --print(str)
    end
    if streamErr and streamErr:CanRead() then
        local str = streamErr:Read(4096)
        --print(str)
    end
end

function ExecCommand(cmd, dir, callback)
    if isRunning then
        --print("isRunning")
        return true
    else
        --print("notRunning")
    end

    proc = wx.wxProcess()
    proc:Redirect()
    proc:Connect(wx.wxEVT_END_PROCESS, function(event)
        execTimer:Stop();
        ReadStream()
        proc = nil
        isRunning = false
        --print("process ended")
        callback()
    end)

    local cwd = wx.wxGetCwd()
    wx.wxSetWorkingDirectory(dir)
    --print(cmd)
    isRunning = true
    local pid = wx.wxExecute(cmd, wx.wxEXEC_ASYNC, proc)     
    --print("PID:" .. tostring(pid))
    wx.wxSetWorkingDirectory(cwd)

    if pid == -1 then
        wx.wxMessageBox("Unknown ERROR in running program!\n" .. cmd, "Error", wx.wxOK + wx.wxCENTRE, frame)
    else
        streamIn = proc and proc:GetInputStream()
        streamErr = proc and proc:GetErrorStream()
        streamOut = proc and proc:GetOutputStream()
        execTimer:Start(200);
    end

    return false
end

frame:Connect(ID.TIMER_EXECUTION, wx.wxEVT_TIMER, ReadStream)

-----------------------------------------------------------
-- Use a timer to update preview image
-----------------------------------------------------------

ID.TIMER_PREVIEW = NewID()
local previewTimer = wx.wxTimer(frame, ID.TIMER_PREVIEW)

dirname = datapath .. sep .. "directory.txt"
texname = datapath .. sep .. "fragment.tex"
pdfname = datapath .. sep .. "fragment.pdf"
pngname = datapath .. sep .. "fragment.png"
cuttedpngname = datapath .. sep .. "fragment-%d.png"

if not engine then engine = "xelatex" end
if not resolution then resolution = 450 end
if not heightlevel then heightlevel = "VM" end
local preamble_genstate
if wx.wxFileName(predefine_preamble):FileExists()then
	preamble_genstate="PD"
else
	preamble_genstate="GEN"
end
	
switch = "-interaction=nonstopmode -output-directory=\"" .. datapath .. "\""

modtime = wx.wxDateTime()

function CheckFileTime()
    local fn = wx.wxFileName(texname)
    if not fn:FileExists() then return false end
    local time = fn:GetModificationTime()
    if time:IsLaterThan(modtime) then
        modtime = time
        return true
    else
        return false
    end
end

function CompileDocument(DoTimeCheck)
    local fn = wx.wxFileName(dirname)
    if not fn:FileExists() then return end
    local file = io.input(dirname)
    local dir = io.read("*line")
    io.close(file)
    if (DoTimeCheck==1 and (not CheckFileTime())) or isRunning then
        --print(modtime:GetTicks())
        return
    end
    local cmd = engine .. " " .. switch .. " \"" .. texname .. "\""
    wx.wxRemoveFile(pdfname)
    --Replace \ to / to resolve http://tex.stackexchange.com/questions/271617/luatex-issue-with-space-in-path
    isPending = ExecCommand(string.gsub(cmd, "\\", "/"), dir, PreviewDocument)
    frame:SetStatusText("  Running " .. engine)
end

function PreviewDocument()
    LocateError()
    local cmd = "mudraw -r " .. tostring(resolution) .. " -o " .. "\"" .. pngname .. "\" \"" .. pdfname .. "\""
    RemoveImage()
	if wx.wxFileName.FileExists(pdfname) then
        ExecCommand(cmd, mainpath, CropBitmap)
        frame:SetStatusText(latexerr .. "  Running mudraw")
    else
        frame:SetStatusText(latexerr .. "  !PDF NOT FOUND")
    end
end

function CropBitmap()
	local width=1600
    if resolution==450 then
    	width=2400
    elseif resolution==600 then
    	width=3200
    end
    local height
    if heightlevel == "VM" then
    	height=width/2
    elseif heightlevel == "VL" then
    	height=width*11/16
    elseif heightlevel == "VS" then
    	height=width*5/16
    end
    local imcmd = "convert \"" .. pngname .. "\" -crop " .. tostring(width) .."x"..tostring(height).." +repage -scene 1 \"" .. cuttedpngname .. "\""
    if wx.wxFileName.FileExists(pngname) then
        ExecCommand(imcmd, mainpath, UpdateBitmap)
        frame:SetStatusText(latexerr .. "  Running ImageMagick")
    else
        frame:SetStatusText(latexerr .. " !PNG NOT FOUND")
    end
end

--function IsEmptyImage()
--    local s = image:GetData()
--    if string.match(s, "^\255+$") then
--    	--print("empty image")
--        return true
--    else
--        return false
--    end
--end

function UpdateBitmap()
    local png = FindImage()
    if png then
    	--print("loading " .. png)
        image:LoadFile(png, wx.wxBITMAP_TYPE_PNG)
        --print("loaded")
        --image:GetData() strangly crashs lua
        --IsEmptyImage removed
        ResizeControl()
    else
    	frame:SetStatusText(latexerr .. " !CUTTED PNG NOT FOUND")
        ClearImage()
        ResizeControl()
    end
end

function NextBitmap()
    local png = NextImage()
    --print("loading next png:" .. png)
    if png and image:LoadFile(png, wx.wxBITMAP_TYPE_PNG) then  
    	--print("loaded")
    	ResizeControl()
    end
end

page = 1
total = 1

function FindImage()
    local png = ""  
    page=1
    while true do
        png = string.format(cuttedpngname, total)
        if wx.wxFileName.FileExists(png) then
            total = total + 1
        else break end
    end
    total = total - 1
    if total > 0 then
    	frame:SetStatusText(latexerr .. "  Page:1 of " .. tostring(total))
        return string.format(cuttedpngname, 1)
    else return nil end
end

function NextImage()
    if total == 1 then do return nil end end
    if page == total then page = 1 else page = page + 1 end
    local png = string.format(cuttedpngname, page)
    if wx.wxFileName.FileExists(png) then
    	frame:SetStatusText(latexerr .. "  Page:" .. tostring(page) .." of " .. tostring(total))
        return png
    else return nil end
end

function RemoveImage()
    local i = 1
    --print("deleting pngs")
    while true do
        if wx.wxRemoveFile(string.format(cuttedpngname, i)) then
            i = i + 1
        else break end
    end
    wx.wxRemoveFile(pngname)
end

function ClearImage()
    for x = 1, image:GetWidth() do
        for y = 1, image:GetHeight() do
            image:SetRGB(x, y, 171, 171, 171)
        end
    end
end

frame:Connect(ID.TIMER_PREVIEW, wx.wxEVT_TIMER, function(event)
	CompileDocument(1)
end)

previewTimer:Start(1000);

preview:Connect(wx.wxEVT_LEFT_DOWN, NextBitmap)

-----------------------------------------------------------
-- Locate first error in log file
-----------------------------------------------------------

logname = datapath .. sep .. "fragment.log"

function LocateError()
    local fn = wx.wxFileName(logname)
    if not fn:FileExists() then return end
    local file = io.input(logname)
    local text = io.read("*all")
    io.close(file)
    local _, _, e1, e2, e3, e4 = string.find(text, "\n! (.-)\nl%.(%d+) (.-)\n(.-)\n")
    if not e1 then
        _, _, e1 = string.find(text, "\nRunaway argument?.-\n! (.-)\n")
    end
    if e1 then
        msg = string.gsub(e1, "\n.*", "")
        if msg == "Undefined control sequence." then
            _, _, cs = string.find(e3, "(\\%a+)$")
            if cs then
                msg = string.sub(msg, 1, -2) .. " " .. cs .. "."
            end
        end
        frame:SetStatusText("! " .. msg)
        latexerr ="! " .. msg
    else
        frame:SetStatusText(engine .. " Success.")
        latexerr=""
    end
end

-----------------------------------------------------------
-- The popup menu
-----------------------------------------------------------

menu = wx.wxMenu()

ID.ENGINE   = NewID()
ID.PDFLATEX = NewID()
ID.XELATEX  = NewID()
ID.LUALATEX = NewID()

menu:Append(ID.ENGINE, "Engine", wx.wxMenu{
    { ID.PDFLATEX, "&PDFLaTeX", "Use PDFLaTeX", wx.wxITEM_RADIO },
    { ID.XELATEX,  "&XeLaTeX",  "Use XeLaTeX",  wx.wxITEM_RADIO },
    { ID.LUALATEX, "&LuaLaTeX", "Use LuaLaTeX", wx.wxITEM_RADIO },
})

menu:Check(ID[string.upper(engine)], true)

menu:AppendSeparator()

ID.RESOLUTION = NewID()
ID.R600       = NewID()
ID.R450       = NewID()
ID.R300       = NewID()

menu:Append(ID.RESOLUTION, "Resolution", wx.wxMenu{
    { ID.R600, "&600dpi",   "High Resolution",   wx.wxITEM_RADIO },
    { ID.R450, "&450dpi", "Medium Resolution", wx.wxITEM_RADIO },
    { ID.R300, "&300dpi",    "Low Resolution",    wx.wxITEM_RADIO },
})

menu:Check(ID["R" .. tostring(resolution)], true)

menu:AppendSeparator()

ID.VHEIGHT  = NewID()
ID.VL       = NewID()
ID.VM       = NewID()
ID.VS       = NewID()

menu:Append(ID.VHEIGHT, "Cutted PNG Height", wx.wxMenu{
	--9:16
    { ID.VL, "&Large",   "9:16",   wx.wxITEM_RADIO },
    --1:2
    { ID.VM, "&Medium", "1:2", wx.wxITEM_RADIO },
    --3:8
    { ID.VS, "&Small",    "3:8",    wx.wxITEM_RADIO },
})

menu:Check(ID[heightlevel], true)

menu:AppendSeparator()

ID.P         = NewID()
ID.PPD       = NewID()
ID.PGEN      = NewID()
ID.PEDIT     = NewID()

menu:Append(ID.P, "Preamble Generation", wx.wxMenu{
    { ID.PPD, "&Predefined",   "Predefined simple environment",   wx.wxITEM_RADIO },
    { ID.PEDIT, "&Edit additional predefined preamble", "Edit additional preamble of the fragment", wx.wxITEM_RADIO },
    { ID.PGEN, "E&xtract from file", "Slower", wx.wxITEM_RADIO },
})
menu:Check(ID["P" .. preamble_genstate], true)

menu:AppendSeparator()

ID.FRAGMENT = NewID()

menu:Append(ID.FRAGMENT, "&Show Fragment Folder", "Open Fragment Folder")

menu:AppendSeparator()

ID.RECOMPILE =NewID()

menu:Append(ID.RECOMPILE , "&Recompile","Recompile fragment.tex")

menu:AppendSeparator()

ID.ABOUT = NewID()

menu:Append(ID.ABOUT, "&About", "About QuadView")

frame:Connect(ID.PDFLATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    engine = "pdflatex"
end)

frame:Connect(ID.XELATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    engine = "xelatex"
end)

frame:Connect(ID.LUALATEX, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    engine = "lualatex"
end)

frame:Connect(ID.R600, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    resolution = 600
end)

frame:Connect(ID.R450, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    resolution = 450
end)

frame:Connect(ID.R300, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    resolution = 300
end)

frame:Connect(ID.VL, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    heightlevel = "VL"
end)

frame:Connect(ID.VM, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    heightlevel = "VM"
end)

frame:Connect(ID.VS, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    heightlevel = "VS"
end)

frame:Connect(ID.FRAGMENT, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    wx.wxExecute("explorer "  .. datapath, wx.wxEXEC_ASYNC)
end)

frame:Connect(ID.PPD, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
	if not wx.wxFileName(predefine_preamble):FileExists() then
		if not wx.wxFileName(predefine_preamble .. ".disabled"):FileExists() then
			file:Create(predefine_preamble, true)
			file:Write("%Contents in this file will be add to the preview fragment\r\n")
    		file:Write("%\\usepackage{XeCJK}\r\n")
    		file:Close()
    	else
    		if not wx.wxRenameFile(predefine_preamble .. ".disabled",predefine_preamble) then
    			wx.wxMessageBox("Unable to rename file to enable predefined preamble!", "Error", wx.wxOK + wx.wxCENTRE, frame)
    		end
    	end
	end
    preamble_genstate="PD"
end)

frame:Connect(ID.PGEN, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    if wx.wxRenameFile(predefine_preamble,predefine_preamble .. ".disabled") then
        preamble_genstate="GEN"
    else
    	wx.wxMessageBox("Unable to rename file predefine_preamble.tex to disable predefined preamble!", "Error", wx.wxOK + wx.wxCENTRE, frame)
    end
end)

frame:Connect(ID.PEDIT, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
	if preamble_genstate=="PD" then
    	wx.wxExecute("notepad \""  .. predefine_preamble .. "\"", wx.wxEXEC_ASYNC)
    else
    	wx.wxMessageBox("Predefined preamble is currently off.", "Info", wx.wxOK + wx.wxCENTRE, frame)
    	wx.wxExecute("notepad \""  .. predefine_preamble .. ".disabled\"", wx.wxEXEC_ASYNC)
    end
end)


frame:Connect(ID.RECOMPILE, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    CompileDocument(0)
end)

frame:Connect(ID.ABOUT, wx.wxEVT_COMMAND_MENU_SELECTED, function(event)
    wx.wxMessageBox("QuadView" .. " " .. VERSION, "ABOUT")
end)

frame:Connect(wx.wxEVT_CONTEXT_MENU, function(event)
    frame:PopupMenu(menu)
end)

-----------------------------------------------------------
-- Show main frame and start event loop
-----------------------------------------------------------

frame:Show(true)

wx.wxGetApp():MainLoop()
