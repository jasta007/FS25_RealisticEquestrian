--[[
    EqMenuPaging.lua
    Works around an RLRM menu bug: after the trailer Transfer view, the Shift+O menu loses its
    Messages, Herdsman, Settings and Events tabs until the save is reloaded.

    RLRM reuses one menu for every open and hides tabs per open mode. The Transfer view shows
    Transfer alone, so the base game's paging element ends up sitting on that page. On the next
    full open, TabbedMenu:updatePages hides Transfer with page updates muted, so the paging
    element never moves off the hidden page, and the tab bar and page selector are rebuilt from
    that stale state. A fresh load works because every page starts enabled on page 1.

    So whenever the open mode differs from the last open, we put the paging back to that
    fresh-load state just before updatePages applies the new mode's tabs.

    The tab bar has a second leftover. The base game's list centres its tabs when they don't
    fill it, and only works that offset out again when they still don't fill it. With our
    Events tab the full menu has more tabs than fit, so after Transfer's single centred tab the
    full tab list kept Transfer's offset: drawn three tabs down, with Messages, Herdsman,
    Settings and Events pushed off the bottom. So before every updatePages we clear that offset;
    the list sets it again whenever the tabs do fit.
]]

EqMenuPaging = {}

local Log = EqLog


--- Put a menu's paging element back to how it is after loading: every page enabled and page 1
--- current. updatePages then disables this mode's hidden pages, as on the first open.
--- @param menu table the RLMenu instance
--- @return boolean reset false when the paging element is missing or unexpected
function EqMenuPaging.reset(menu)
    local paging = menu.pagingElement
    if paging == nil or type(paging.pages) ~= "table" or #paging.pages == 0
        or paging.setPageIdDisabled == nil or paging.updatePageMapping == nil then
        return false
    end

    -- Muted, as updatePages does, so no page is opened while the menu is still closed.
    paging.neuterPageUpdates = true
    for _, page in ipairs(paging.pages) do
        if page.disabled then
            paging:setPageIdDisabled(page.id, false)
        end
    end
    paging.currentPageIndex = 1
    paging.currentPageMappingIndex = 1
    paging:updatePageMapping()
    paging.neuterPageUpdates = false

    -- The tab bar's saved scroll belongs to the old mode's tab list.
    menu.restorePageScrollOffset = 0
    return true
end


--- Clear the tab list's centring offset, left over from a mode with fewer tabs.
--- @param menu table the RLMenu instance
--- @return boolean cleared true when there was an offset to clear
function EqMenuPaging.clearTabOffset(menu)
    local list = menu.pagingTabList
    if type(list) ~= "table" or type(list.listItemAlignmentOffset) ~= "number" or list.listItemAlignmentOffset == 0 then
        return false
    end
    list.listItemAlignmentOffset = 0
    return true
end


--- Reset the paging when the open mode changed since the last open; called before updatePages.
--- @param menu table the RLMenu instance
function EqMenuPaging.beforeUpdatePages(menu)
    if EqMenuPaging.clearTabOffset(menu) then
        Log:debug("EqMenuPaging: cleared the tab list's centring offset")
    end

    local mode = menu.openMode
    local lastMode = menu.eqLastPagingMode
    menu.eqLastPagingMode = mode

    if lastMode == nil or lastMode == mode then return end

    local ok = EqMenuPaging.reset(menu)
    Log:debug("EqMenuPaging: open mode %s -> %s, paging reset=%s", tostring(lastMode), tostring(mode), tostring(ok))
end


--- One log line with the tab list's layout state, to find where the tabs are drawn.
--- @param menu table the RLMenu instance
--- @param when string
function EqMenuPaging.logTabList(menu, when)
    local list = menu.pagingTabList
    if type(list) ~= "table" then return end
    local function n(v) return type(v) == "number" and string.format("%.4f", v) or tostring(v) end
    local function pair(v) return type(v) == "table" and (n(v[1]) .. "," .. n(v[2])) or tostring(v) end
    local cells = {}
    local section = type(list.sections) == "table" and list.sections[1] or nil
    if section ~= nil and type(section.cells) == "table" then
        for i = 1, 12 do
            local cell = section.cells[i]
            if cell ~= nil then
                cells[#cells + 1] = string.format("%d@%s/%s", i, n(cell.position and cell.position[2]), n(cell.absPosition and cell.absPosition[2]))
            end
        end
    end
    Log:info("EqMenuPaging %s: mode=%s enabled=%s align=%s alignOffset=%s view=%s target=%s content=%s pos=%s abs=%s size=%s abssize=%s elements=%d cells=[%s]",
        when, tostring(menu.openMode), tostring(type(menu.enabledPages) == "table" and #menu.enabledPages or nil),
        n(list.listItemAlignment), n(list.listItemAlignmentOffset), n(list.viewOffset), n(list.targetViewOffset),
        n(list.contentSize), pair(list.position), pair(list.absPosition), pair(list.size), pair(list.absSize),
        type(list.elements) == "table" and #list.elements or -1, table.concat(cells, " "))
end


--- Hook RLMenu's updatePages (inherited from TabbedMenu). Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqMenuPaging.install(guarded)
    local rlMenu = EqRLRM.get("RLMenu")
    rlMenu.updatePages = Utils.prependedFunction(rlMenu.updatePages, function(menu)
        guarded("menu paging reset", function()
            EqMenuPaging.logTabList(menu, "before updatePages")
            EqMenuPaging.beforeUpdatePages(menu)
        end)
    end)
    rlMenu.onOpen = Utils.appendedFunction(rlMenu.onOpen, function(menu)
        guarded("menu tab log", function() EqMenuPaging.logTabList(menu, "after open") end)
    end)
    Log:debug("EqMenuPaging: hooked RLMenu:updatePages")
end
