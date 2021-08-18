local CityEventHelper = GameMain:GetMod("apxCityEventHelper");

-- In C# it would've been just a cast:  (Region.SolveWay) decision
-- However, I didn't find a way to do it from Lua, therefore this mapping
local SolveWayEnumMapping = {
    [0] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.None,
    [1] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Social,
    [2] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Fight,
    [3] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Charm,
    [4] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Intelligence,
    [5] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Food,
    [6] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.LingStone,
    [7] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Wood,
    [8] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Rock,
    [9] = CS.XiaWorld.OutspreadMgr.Region.SolveWay.Member,
};

-- Based on methods from Scripts/MapStory/MapStory.lua
-- We consider such outcomes positive
local EventResultPositive = {
    IncreaseAllPop = 1,
    SlightlyIncreaseAllPop = 2,

    IncreasePop = 3,
    SlightlyIncreasePop = 4,

    HugeIncreaseStab = 5,
    IncreaseStab = 6,
    SlightlyIncreaseStab = 7,

    GreatlyIncreaseAttra = 8,
    IncreaseAttra = 9,
    SlightlyIncreaseAttra = 10,

    DecreaseOtherAttra = 11,
    SlightlyDecreaseOtherAttra = 12,

    DecreaseOtherPop = 13,
    SlightlyDecreaseOtherPop = 14,

    DirectlyGrabOtherPop = 15,
    DirectlyGrabOtherPopSlightly = 16,
};

-- Based on methods from Scripts/MapStory/MapStory.lua
-- We consider such outcomes negative
local EventResultNegative = {
    DecreasePop = 1,
    SlightlyDecreasePop = 2,

    DecreaseAllPop = 3,
    SlightlyDecreaseAllPop = 4,

    IncreaseOtherPop = 5,
    SlightlyIncreaseOtherPop = 6,

    IncreaseOtherAttra = 7,
    SlightlyIncreaseOtherAttra = 8,

    HugeDecreaseStab = 9,
    DecreaseStab = 10,
    SlightlyDecreaseStab = 11,

    DecreaseAttra = 12,
    SlightlyDecreaseAttra = 13,

    DisasterAffectAllPop = 14,
    DisasterDecreaseAllPop = 15,
};

-- Based on methods from Scripts/MapStory/MapStory.lua
-- We consider such outcomes neutral
local EventResultNeutral = {
    NoEvent = 1,
};

-- Prevent multiple registration of the same hooks
local CityWindowHookRegistered = false;
local CityEventWindowHookRegistered = false;
local ChangeFlag = false;
local TimePassed = 0;

function CityEventHelper:OnInit()
    -- Expose private methods of some classes
    xlua.private_accessible(CS.Wnd_QuickCityWindow);
    xlua.private_accessible(CS.XiaWorld.MapStoryMgr);
    xlua.private_accessible(CS.FairyGUI.GObject);
    CityEventHelper:Log("Private classes are exposed");
end

function CityEventHelper:OnEnter()
    -- Setup a hook to trigger when city window is shown
    if CityWindowHookRegistered == false then
        local Wnd_QuickCityWindow = CS.Wnd_QuickCityWindow.Instance;
        Wnd_QuickCityWindow.onAddedToStage:Add(function() CityEventHelper:OnWnd_QuickCityWindowAdded(Wnd_QuickCityWindow); end)
        CityEventHelper:Log("Hooked city window display event");
        CityWindowHookRegistered = true;
    end
end

function CityEventHelper:OnWnd_QuickCityWindowAdded(Wnd_QuickCityWindow)
    -- Setup a hook to trigger when city event window is shown
    if CityEventWindowHookRegistered == false then
        Wnd_QuickCityWindow.UIInfo.m_buildtype.onChanged:Add(function()
            if Wnd_QuickCityWindow.UIInfo.m_buildtype.selectedIndex == 2 then
                ChangeFlag = true;
            end
        end)
        CityEventHelper:Log("Hooked city event window state change");
        CityEventWindowHookRegistered = true;
    end
end

-- This is a workaround to overcome concurrent UI modification
-- We will wait for ~100ms after the event is handled by the game
function CityEventHelper:OnRender(dt)
    -- dt is seconds since last tick
    if ChangeFlag == true then
        TimePassed = TimePassed + dt;
        if TimePassed > 0.1 then
            ChangeFlag = false;
            TimePassed = 0;
            CityEventHelper:UpdateCityEventWindow();
        end
    end
end

-- This event will happen when the city event window will be shown (the one with buttons to select the solution)
function CityEventHelper:UpdateCityEventWindow()
    local Wnd_QuickCityWindow = CS.Wnd_QuickCityWindow.Instance;
    CityEventHelper:Log("City event window is displayed");

    -- Ensure that region is set
    if Wnd_QuickCityWindow.curregion ~= nil then
        -- This is the current region (of type XiaWorld.OutspreadMgr.Region)
        local region = Wnd_QuickCityWindow.curregion;
        -- Fetch the event story definition
        local policyStoryDef = CS.XiaWorld.OutspreadMgr.Instance:GetPolicyStoryDef(region.RegionPolicy.PolicyStory);
        -- This is the internal name of the current event
        local policyName = policyStoryDef.Story;
        -- Fetch the full event data (defined in Settings/MapStories/MapStory_Policy.xml)
        local storyDef = MapStoryMgr:GetStoryDef(policyName);
        -- Event data has the Lua code to check the result. It is placed under the specific path
        local eventResultCode = storyDef.Selections[0].OKResult;

        CityEventHelper:Log("Detected event with policy name:", policyName, "| Region:", region.RegionName);

        -- Let's iterate over the buttons
        local buttonsList = Wnd_QuickCityWindow.UIInfo.m_n31;
        for i = 0, 8 do
            local button = buttonsList:GetChildAt(i);
            -- Id of the decision (can be cast to XiaWorld.OutspreadMgr.Region.SolveWay)
            local decisionId = button.data;
            -- We will evaluate event code against this decision to see the possible outcome
            local result = CityEventHelper:EvaluateEventCode(eventResultCode, region, decisionId);

            -- Now find out outcome of the decision and update the buttons
            local titleUpdate = "";
            local descriptionUpdate = "";
            local positiveEffectsCount = 0;
            local negativeEffectsCount = 0;

            for key, value in pairs(result) do
                if EventResultPositive[key] ~= nil then
                    positiveEffectsCount = positiveEffectsCount + 1;
                    descriptionUpdate = descriptionUpdate.."\n".."<font color=#009600>"..key.."</font>";
                end
                if EventResultNegative[key] ~= nil then
                    negativeEffectsCount = negativeEffectsCount + 1;
                    descriptionUpdate = descriptionUpdate.."\n".."<font color=#D06508>"..key.."</font>";
                end
                if EventResultNeutral[key] ~= nil then
                    descriptionUpdate = descriptionUpdate.."\n"..key;
                end
            end
            -- CityEventHelper:Log("Decision:", decisionId, " | Updating title with:", titleUpdate, " | Elem:", button.name);

            -- Calculate button title update based on the events
            if positiveEffectsCount > 0 and negativeEffectsCount > 0 then
                titleUpdate = "(~)";
            elseif positiveEffectsCount > 0 then
                titleUpdate = "(+)";
            elseif negativeEffectsCount > 0 then
                titleUpdate = "(-)";
            end

            -- Update the button title
            if decisionId == 6 then
                -- Adjust spirit stones translation (too long)
                button.title = "Spirit"..titleUpdate;
            else
                -- Use normal title
                button.title = CS.XiaWorld.GameDefine.SolveWayToStr[decisionId]..titleUpdate;
            end

            -- Add specific event result into the tooltip
            if descriptionUpdate ~= "" then
                -- CityEventHelper:Log("Decision:", decisionId, " | Updating desc", " | Elem:", button.name);
                button.tooltips = CS.XiaWorld.GameDefine.SolveWayToDes[decisionId].."\n"..descriptionUpdate;
            end
        end
    end
end

-- This method evaluates village event code in the mocked context to predict the outcome
function CityEventHelper:EvaluateEventCode(eventResultCode, region, decision)
    -- This is a real Lua mod which handles the village event evaluation
    local RealMapStoryHelper = GameMain:GetMod("MapStoryHelper");

    -- We're using some meta-magic here to track the calls instead of MapStoryHelper
    local EventResult = { };
    local MockMetaTable = { };
    function MockMetaTable.__index(s, k)
        -- Store called method in the result table
        EventResult[k] = 1;

        -- We proxy these methods to the real calls, they're checking the stat threshold (like 15+ social etc)
        if k == "MPL" then
            return RealMapStoryHelper.MPL;
        elseif k == "SPL" then
            return RealMapStoryHelper.SPL;
        elseif k == "SML" then
            return RealMapStoryHelper.SML;
        elseif k == "MPP" then
            return RealMapStoryHelper.MPP;
        elseif k == "SPP" then
            return RealMapStoryHelper.SPP;
        elseif k == "SMP" then
            return RealMapStoryHelper.SMP;
        end
        -- Return stub function to avoid any errors
        return function() end;
    end
    local MockStoryHelper = {}
    setmetatable(MockStoryHelper, MockMetaTable)

    -- Construct mocked environment
    local testContext = {
        story = {
            target = {
                region = {
                    UnionData = region.UnionData,
                    RegionPolicy = {
                        Way = SolveWayEnumMapping[decision] -- We're passing our decision here
                    }
                }
            }
        },
        GameMain = {
            GetMod = function () return MockStoryHelper; end
        },
        WorldLua = {
            AddMsg = function() end
        },
        CS = {
            XiaWorld = {
                OutspreadMgr = {
                    Region = {
                        SolveWay = CS.XiaWorld.OutspreadMgr.Region.SolveWay
                    },
                    Instance = {
                        -- These functions used in calculations. We only leave one without side effects and mock another one
                        CanCostItem = function(self, item, amount) return CS.XiaWorld.OutspreadMgr.Instance:CanCostItem(item, amount); end,
                        CostItem = function() end
                    }
                }
            }
        },
        XT = function() end
    };

    local status, err = pcall(function ()
        local fn = load(eventResultCode, nil, "t", testContext);
        fn();
    end)
    if err ~= nil then
        CityEventHelper:Log("Decision:", decision, "| Eval failed:", err);
    end
    return EventResult;
end

function CityEventHelper:Log(...)
    local arg = {...};
    local str = "[CityEventHelper] ";
    for i, v in ipairs(arg) do
        if v ~= nil then
            str = str .. tostring(v) .. " "
        else
            str = str .. "nil "
        end
    end
    print(str)
end
