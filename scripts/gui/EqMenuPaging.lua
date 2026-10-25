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


--- Reset the paging when the open mode changed since the last open; called before updatePages.
--- @param menu table the RLMenu instance
function EqMenuPaging.beforeUpdatePages(menu)
    local mode = menu.openMode
    local lastMode = menu.eqLastPagingMode
    menu.eqLastPagingMode = mode

    if lastMode == nil or lastMode == mode then return end

    local ok = EqMenuPaging.reset(menu)
    Log:debug("EqMenuPaging: open mode %s -> %s, paging reset=%s", tostring(lastMode), tostring(mode), tostring(ok))
end


--- Hook RLMenu's updatePages (inherited from TabbedMenu). Call once, after EqRLRM.init succeeded.
--- @param guarded function main.lua's error guard
function EqMenuPaging.install(guarded)
    local rlMenu = EqRLRM.get("RLMenu")
    rlMenu.updatePages = Utils.prependedFunction(rlMenu.updatePages, function(menu)
        guarded("menu paging reset", function() EqMenuPaging.beforeUpdatePages(menu) end)
    end)
    Log:debug("EqMenuPaging: hooked RLMenu:updatePages")
end
