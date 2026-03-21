--[[
* Window Background Library for Whispers
* Adapted from XIUI windowbackground.lua
*
* The 5-piece system:
*   bg     - main background texture (scaled, tiled)
*   tl, tr, bl, br - L-shaped corner/edge border pieces (not scaled)
*
* Theme types:
*   '-None-' : Hidden
*   'Plain'  : Background only, no borders
*   'Window1'-'Window8': Background + decorative border corners
]]--

require('common');
local primitives = require('primitives');

local M = {};

local BORDER_KEYS = { 'tl', 'tr', 'br', 'bl' };
local DEFAULT_PADDING = 8;
local DEFAULT_BORDER_SIZE = 21;
local DEFAULT_BG_OFFSET = 1;

local function IsWindowTheme(name)
    return name ~= nil and name:match('^Window%d+$') ~= nil;
end

local function ApplyOpacity(color, opacity)
    local a = math.floor(math.max(0, math.min(1, opacity or 1.0)) * 255);
    local rgb = bit.band(color or 0xFFFFFFFF, 0x00FFFFFF);
    return bit.bor(bit.lshift(a, 24), rgb);
end

local function make_prim()
    local p = primitives:new({
        visible = false,
        can_focus = false,
        locked = true,
        position_x = 0,
        position_y = 0,
        width = 16,
        height = 16,
        color = 0xFFFFFFFF,
    });
    p.exists = false;
    return p;
end

--[[
    Create a complete window background handle.
    Call once at init time; pass the returned handle to update() each frame.

    @param themeName string  : '-None-', 'Plain', or 'Window1'-'Window8'
    @param bgScale   number  : background texture scale (default 1.0)
    @param borderScale number: border texture scale     (default 1.0)
    @return table: handle with bg, tl, tr, bl, br primitives
]]--
function M.create(themeName, bgScale, borderScale)
    themeName   = themeName   or '-None-';
    bgScale     = bgScale     or 1.0;
    borderScale = borderScale or 1.0;

    local handle = {
        themeName   = themeName,
        bgScale     = bgScale,
        borderScale = borderScale,
    };

    -- Background primitive
    local bgPrim = make_prim();
    bgPrim.scale_x = bgScale;
    bgPrim.scale_y = bgScale;
    if themeName ~= '-None-' then
        local fp = ('%s/assets/backgrounds/%s-bg.png'):format(addon.path, themeName);
        bgPrim.texture = fp;
        bgPrim.exists  = ashita.fs.exists(fp);
    end
    handle.bg = bgPrim;

    -- Border primitives
    for _, k in ipairs(BORDER_KEYS) do
        local prim = make_prim();
        prim.scale_x = borderScale;
        prim.scale_y = borderScale;
        if IsWindowTheme(themeName) then
            local fp = ('%s/assets/backgrounds/%s-%s.png'):format(addon.path, themeName, k);
            prim.texture = fp;
            prim.exists  = ashita.fs.exists(fp);
        end
        handle[k] = prim;
    end

    return handle;
end

--[[
    Update primitive positions and visibility each frame.
    Must be called inside imgui.Begin() so window pos/size are current.

    @param handle  table : handle from create()
    @param x,y     number: window top-left position
    @param w,h     number: window width/height
    @param options table : {
        theme       = string,   -- override theme for visibility logic
        bgOpacity   = number,   -- 0–1 (default 1.0)
        borderOpacity = number, -- 0–1 (defaults to bgOpacity)
        padding     = number,   -- px to extend bg beyond window edges (default 8)
    }
]]--
function M.update(handle, x, y, w, h, options)
    if not handle then return; end
    options = options or {};

    local theme        = options.theme or handle.themeName or '-None-';
    local padding      = options.padding or DEFAULT_PADDING;
    local bgOpacity    = options.bgOpacity or 1.0;
    local borderOpacity = options.borderOpacity or bgOpacity;
    local bgColor      = ApplyOpacity(0xFFFFFFFF, bgOpacity);
    local borderColor  = ApplyOpacity(0xFFFFFFFF, borderOpacity);
    local bgScale      = handle.bgScale     or 1.0;
    local borderScale  = handle.borderScale or 1.0;

    -- ---- Background ----
    local bgPrim = handle.bg;
    if theme == '-None-' then
        bgPrim.visible = false;
    else
        local bgW = w + padding * 2;
        local bgH = h + padding * 2;
        bgPrim.position_x = x - padding;
        bgPrim.position_y = y - padding;
        bgPrim.width      = math.ceil(bgW / bgScale);
        bgPrim.height     = math.ceil(bgH / bgScale);
        bgPrim.scale_x    = bgScale;
        bgPrim.scale_y    = bgScale;
        bgPrim.color      = bgColor;
        bgPrim.visible    = bgPrim.exists;
    end

    -- ---- Borders (Window themes only) ----
    if not IsWindowTheme(theme) then
        for _, k in ipairs(BORDER_KEYS) do
            if handle[k] then handle[k].visible = false; end
        end
        return;
    end

    local borderSize = DEFAULT_BORDER_SIZE;
    local bgOffset   = DEFAULT_BG_OFFSET;

    local bgW = w + padding * 2;
    local bgH = h + padding * 2;
    local bgX = x - padding;
    local bgY = y - padding;

    local br = handle.br;
    br.position_x = bgX + bgW - math.floor(borderSize * borderScale - bgOffset * borderScale);
    br.position_y = bgY + bgH - math.floor(borderSize * borderScale - bgOffset * borderScale);
    br.width      = borderSize;
    br.height     = borderSize;
    br.color      = borderColor;
    br.scale_x    = borderScale;
    br.scale_y    = borderScale;
    br.visible    = br.exists;

    local tr = handle.tr;
    tr.position_x = br.position_x;
    tr.position_y = bgY - bgOffset * borderScale;
    tr.width      = borderSize;
    tr.height     = math.ceil((br.position_y - tr.position_y) / borderScale);
    tr.color      = borderColor;
    tr.scale_x    = borderScale;
    tr.scale_y    = borderScale;
    tr.visible    = tr.exists;

    local tl = handle.tl;
    tl.position_x = bgX - bgOffset * borderScale;
    tl.position_y = bgY - bgOffset * borderScale;
    tl.width      = math.ceil((tr.position_x - tl.position_x) / borderScale);
    tl.height     = tr.height;
    tl.color      = borderColor;
    tl.scale_x    = borderScale;
    tl.scale_y    = borderScale;
    tl.visible    = tl.exists;

    local bl = handle.bl;
    bl.position_x = tl.position_x;
    bl.position_y = br.position_y;
    bl.width      = tl.width;
    bl.height     = br.height;
    bl.color      = borderColor;
    bl.scale_x    = borderScale;
    bl.scale_y    = borderScale;
    bl.visible    = bl.exists;
end

--[[
    Change theme; only reloads textures if the theme actually changed.

    @param handle    table : handle from create()
    @param themeName string: new theme name
    @param bgScale   number: optional new bg scale
    @param borderScale number: optional new border scale
]]--
function M.setTheme(handle, themeName, bgScale, borderScale)
    if not handle then return; end

    local oldTheme = handle.themeName;
    handle.themeName = themeName;

    if bgScale then
        handle.bgScale    = bgScale;
        handle.bg.scale_x = bgScale;
        handle.bg.scale_y = bgScale;
    end
    if borderScale then
        handle.borderScale = borderScale;
        for _, k in ipairs(BORDER_KEYS) do
            if handle[k] then
                handle[k].scale_x = borderScale;
                handle[k].scale_y = borderScale;
            end
        end
    end

    if oldTheme == themeName then return; end

    -- Reload bg texture
    local bgPrim = handle.bg;
    if themeName == '-None-' then
        bgPrim.exists  = false;
        bgPrim.visible = false;
    else
        local fp = ('%s/assets/backgrounds/%s-bg.png'):format(addon.path, themeName);
        bgPrim.texture = fp;
        bgPrim.exists  = ashita.fs.exists(fp);
    end

    -- Reload border textures
    local isWindow = IsWindowTheme(themeName);
    for _, k in ipairs(BORDER_KEYS) do
        local prim = handle[k];
        if prim then
            if isWindow then
                local fp = ('%s/assets/backgrounds/%s-%s.png'):format(addon.path, themeName, k);
                prim.texture = fp;
                prim.exists  = ashita.fs.exists(fp);
            else
                prim.exists  = false;
                prim.visible = false;
            end
        end
    end
end

--[[
    Hide all primitives (use when window is closed/minimized).
]]--
function M.hide(handle)
    if not handle then return; end
    if handle.bg then handle.bg.visible = false; end
    for _, k in ipairs(BORDER_KEYS) do
        if handle[k] then handle[k].visible = false; end
    end
end

--[[
    Destroy all primitives (call at addon unload).
]]--
function M.destroy(handle)
    if not handle then return; end
    if handle.bg then handle.bg:destroy(); end
    for _, k in ipairs(BORDER_KEYS) do
        if handle[k] then handle[k]:destroy(); end
    end
end

return M;
