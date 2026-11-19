-- Owned shops: the stores players can buy, run and stock. Generated on 2026-11-19 from the lc_stores config it replaces
-- (same prices and products). Spots are NOT taken from lc_stores: DPS runs TStudio and other store maps, so an admin places
-- each store in game (/shopoffice, /shopcounter). lcOffice/lcCounters are only where lc_stores had them, as a hint.
Config.Owned = {
    Enabled = true,  -- false: owned shops off (lc_stores still runs these spots until step 4)
    MaxStoresPerPlayer = 1,  -- stores one character can own
    MaxStoresEmployed = 2,   -- stores one character can work at
    UnownedFullStock = true,  -- a store nobody owns sells its default products without running out
    InstantRestock = true,  -- step 1 only: ordering stock lands at once. Step 2 replaces it with delivery runs.
    PayAccounts = { "bank", "cash" },  -- what a customer can pay with
    StoreAccount = "bank",  -- owner deposits and withdrawals go to and from this account
    Inactive = { active = true, minStock = 30, minVariety = 70, hours = 72 },
    -- 1 basic, 2 advanced, 3 full, 4 owner only
    Roles = {
        buyCategory = 3,
        buyUpgrade = 2,
        changeRole = 3,
        createJob = 2,
        deleteJob = 2,
        depositMoney = 3,
        firePlayer = 3,
        giveCommission = 3,
        hideBalance = 2,
        hirePlayer = 3,
        renameStore = 3,
        sellCategory = 3,
        sellStore = 4,
        setPrice = 2,
        showBalance = 2,
        startExportJob = 1,
        startImportJob = 1,
        storeProductFromInventory = 1,
        withdrawMoney = 3,
    },
    RoleNames = { [1] = "Clerk", [2] = "Manager", [3] = "Partner", [4] = "Owner" },
    Types = {
        ["247store"] = {
            capacity = 150, maxStaff = 5, maxCategories = 4,
            requiredJob = {  },  -- jobs that may buy here ({} = everyone)
            categories = { "food_market", "drink_market", "alcohol_market", "electronics_market", "utilities_market" },
            defaultCategories = { "food_market", "drink_market", "alcohol_market", "electronics_market", "utilities_market" },
            upgrades = {
                relationship = { price = 11000, levels = { 0, 5, 10, 15, 25, 40 } },
                stock = { price = 8000, levels = { 0, 50, 100, 150, 200, 300 } },
                truck = { price = 12000, levels = { 0, 25, 50, 100, 200, 300 } },
            },
            trucks = { "speedo", "gburrito", "mule", "mule3", "pounder", "pounder2" },  -- by truck upgrade level, for step 2 restock runs
            blip = { sprite = 0, colour = 4, scale = 0.6, label = "Market" },
        },
        ["ammunation"] = {
            capacity = 50, maxStaff = 5, maxCategories = 4,
            requiredJob = { "police" },  -- jobs that may buy here ({} = everyone)
            categories = { "melee_weapons", "pistol_weapons", "rifle_weapons", "shotgun_weapons", "smg_weapons", "throwable_weapons", "ammo_weapons", "others_weapons" },
            defaultCategories = { "melee_weapons", "pistol_weapons", "ammo_weapons", "others_weapons" },
            upgrades = {
                relationship = { price = 32000, levels = { 0, 3, 5, 8, 10, 15 } },
                stock = { price = 16000, levels = { 0, 10, 20, 30, 40, 50 } },
                truck = { price = 25000, levels = { 0, 10, 20, 40, 70, 90 } },
            },
            trucks = { "speedo", "gburrito", "mule", "mule3", "pounder", "pounder2" },  -- by truck upgrade level, for step 2 restock runs
            blip = { sprite = 0, colour = 4, scale = 0.6, label = "Ammunation" },
        },
    },
    Categories = {
        ["alcohol_market"] = { label = "Alcohol", buyPrice = 2500, sellPrice = 1250, items = {
            ["beer"] = { label = "Beer", price = 7, min = 3, max = 14, cost = 5, export = 6, batch = 35 },
            ["vodka"] = { label = "Vodka", price = 12, min = 6, max = 24, cost = 9, export = 11, batch = 35 },
            ["whiskey"] = { label = "Whiskey", price = 10, min = 5, max = 20, cost = 7, export = 100, batch = 35 },
            ["wine"] = { label = "Wine", price = 15, min = 7, max = 30, cost = 10, export = 14, batch = 35 },
        } },
        ["ammo_weapons"] = { label = "Ammo", buyPrice = 35000, sellPrice = 17500, items = {
            ["pistol_ammo"] = { label = "Pistol Ammo", price = 250, min = 125, max = 500, cost = 150, export = 200, batch = 100 },
            ["rifle_ammo"] = { label = "Rifle Ammo", price = 350, min = 175, max = 700, cost = 250, export = 300, batch = 100 },
            ["shotgun_ammo"] = { label = "Shotgun Ammo", price = 300, min = 150, max = 600, cost = 225, export = 250, batch = 100 },
            ["smg_ammo"] = { label = "SMG Ammo", price = 300, min = 150, max = 600, cost = 225, export = 250, batch = 100 },
        } },
        ["drink_market"] = { label = "Drinks", buyPrice = 5000, sellPrice = 2500, items = {
            ["coffee"] = { label = "Coffee", price = 4, min = 2, max = 8, cost = 3, export = 3, batch = 35 },
            ["grapejuice"] = { label = "Grape Juice", price = 10, min = 5, max = 20, cost = 7, export = 8, batch = 35 },
            ["kurkakola"] = { label = "Cola", price = 4, min = 2, max = 8, cost = 3, export = 3, batch = 35 },
            ["water_bottle"] = { label = "Bottle of Water", price = 4, min = 2, max = 8, cost = 3, export = 3, batch = 35 },
        } },
        ["electronics_market"] = { label = "Electronics", buyPrice = 5000, sellPrice = 2500, items = {
            ["iphone"] = { label = "iPhone", price = 1000, min = 500, max = 2000, cost = 500, export = 850, batch = 2 },
            ["laptop"] = { label = "Laptop", price = 700, min = 350, max = 1400, cost = 350, export = 490, batch = 2 },
            ["phone"] = { label = "Phone", price = 850, min = 425, max = 1700, cost = 425, export = 637, batch = 2 },
            ["radio"] = { label = "Radio", price = 200, min = 100, max = 400, cost = 100, export = 150, batch = 2 },
            ["samsungphone"] = { label = "Samsung S10", price = 950, min = 475, max = 1900, cost = 475, export = 665, batch = 2 },
            ["tablet"] = { label = "Tablet", price = 600, min = 300, max = 1200, cost = 300, export = 420, batch = 2 },
        } },
        ["food_market"] = { label = "Food", buyPrice = 5000, sellPrice = 2500, items = {
            ["sandwich"] = { label = "Sandwich", price = 3, min = 1, max = 6, cost = 2, export = 4, batch = 35 },
            ["snikkel_candy"] = { label = "Snikkel", price = 3, min = 1, max = 6, cost = 2, export = 4, batch = 35 },
            ["tosti"] = { label = "Grilled Sandwich", price = 4, min = 1, max = 6, cost = 2, export = 4, batch = 35 },
            ["twerks_candy"] = { label = "Twerks", price = 3, min = 1, max = 6, cost = 2, export = 4, batch = 35 },
        } },
        ["melee_weapons"] = { label = "Melee Weapons", buyPrice = 10000, sellPrice = 5000, items = {
            ["weapon_bat"] = { label = "Baseball Bat", price = 500, min = 250, max = 1000, cost = 375, export = 750, batch = 2 },
            ["weapon_crowbar"] = { label = "Crowbar", price = 500, min = 250, max = 1000, cost = 375, export = 750, batch = 2 },
            ["weapon_hammer"] = { label = "Hammer", price = 250, min = 125, max = 500, cost = 250, export = 250, batch = 2 },
            ["weapon_knife"] = { label = "Knife", price = 250, min = 125, max = 500, cost = 188, export = 375, batch = 2 },
            ["weapon_wrench"] = { label = "Wrench", price = 250, min = 125, max = 500, cost = 250, export = 250, batch = 2 },
        } },
        ["others_weapons"] = { label = "Miscellaneous", buyPrice = 5000, sellPrice = 2500, items = {
            ["armor"] = { label = "Armor", price = 5500, min = 2750, max = 11000, cost = 4125, export = 4500, batch = 2 },
            ["parachute"] = { label = "Parachute", price = 2500, min = 1250, max = 5000, cost = 1875, export = 2500, batch = 5 },
            ["weapon_flaregun"] = { label = "Flare Gun", price = 1000, min = 500, max = 2000, cost = 675, export = 750, batch = 5 },
        } },
        ["pistol_weapons"] = { label = "Pistol Weapons", buyPrice = 25000, sellPrice = 12500, items = {
            ["weapon_pistol"] = { label = "Pistol", price = 2500, min = 1250, max = 5000, cost = 1875, export = 2500, batch = 1 },
            ["weapon_snspistol"] = { label = "SNS Pistol", price = 1500, min = 750, max = 3000, cost = 1200, export = 1350, batch = 1 },
            ["weapon_vintagepistol"] = { label = "Vintage Pistol", price = 4000, min = 2000, max = 8000, cost = 3000, export = 3600, batch = 1 },
        } },
        ["rifle_weapons"] = { label = "Rifle Weapons", buyPrice = 60000, sellPrice = 30000, items = {
            ["weapon_assaultrifle"] = { label = "Assault Rifle", price = 25000, min = 12500, max = 50000, cost = 18750, export = 25000, batch = 1 },
            ["weapon_carbinerifle"] = { label = "Carbine Rifle", price = 40000, min = 20000, max = 80000, cost = 30000, export = 36000, batch = 1 },
        } },
        ["shotgun_weapons"] = { label = "Shotgun Weapons", buyPrice = 60000, sellPrice = 30000, items = {
            ["weapon_pumpshotgun"] = { label = "Pump Shotgun", price = 25000, min = 12500, max = 50000, cost = 18750, export = 25000, batch = 1 },
        } },
        ["smg_weapons"] = { label = "SMG Weapons", buyPrice = 50000, sellPrice = 25000, items = {
            ["weapon_microsmg"] = { label = "Micro SMG", price = 15000, min = 7500, max = 30000, cost = 11250, export = 12000, batch = 1 },
            ["weapon_smg"] = { label = "SMG", price = 17000, min = 8500, max = 34000, cost = 12750, export = 14000, batch = 1 },
        } },
        ["throwable_weapons"] = { label = "Throwable Weapons", buyPrice = 40000, sellPrice = 20000, items = {
            ["weapon_flare"] = { label = "Flare", price = 700, min = 350, max = 1400, cost = 475, export = 550, batch = 1 },
            ["weapon_molotov"] = { label = "Molotov", price = 1600, min = 800, max = 3200, cost = 1200, export = 1325, batch = 1 },
        } },
        ["utilities_market"] = { label = "Utilities", buyPrice = 3000, sellPrice = 1500, items = {
            ["cleaningkit"] = { label = "Cleaning Kit", price = 150, min = 75, max = 300, cost = 125, export = 135, batch = 2 },
            ["repairkit"] = { label = "Repairkit", price = 250, min = 125, max = 500, cost = 200, export = 225, batch = 2 },
            ["screwdriverset"] = { label = "Toolkit", price = 350, min = 175, max = 700, cost = 300, export = 315, batch = 2 },
        } },
    },
    Stores = {
        { id = "ammunation_1", type = "ammunation", buyPrice = 2000000, sellPrice = 500000,
          lcOffice = vec3(14.47, -1106.08, 29.80), blip = vec3(20.91, -1110.49, 29.79), garage = vec4(27.71, -1113.25, 29.30, 329.89), delivery = vec3(18.89, -1116.02, 29.79),
          lcCounters = { vec3(22.64, -1106.88, 29.80), vec3(20.91, -1110.49, 29.80), vec3(19.58, -1109.95, 29.80) } },
        { id = "market_1", type = "247store", buyPrice = 220000, sellPrice = 110000,
          lcOffice = vec3(-709.57, -905.79, 19.22), blip = vec3(-714.77, -912.22, 19.21), garage = vec4(-707.13, -924.98, 19.02, 179.01), delivery = vec3(-714.55, -917.80, 19.22),
          lcCounters = { vec3(-714.78, -912.23, 19.22), vec3(-707.41, -913.48, 19.22), vec3(-711.70, -912.08, 19.22) } },
        { id = "market_2", type = "247store", buyPrice = 300000, sellPrice = 150000,
          lcOffice = vec3(30.24, -1339.28, 29.50), blip = vec3(25.71, -1346.47, 29.49), garage = vec4(15.30, -1345.17, 29.29, 179.17), delivery = vec3(22.91, -1350.33, 29.33),
          lcCounters = { vec3(25.71, -1346.47, 29.50), vec3(29.21, -1342.60, 29.50) } },
        { id = "market_3", type = "247store", buyPrice = 110000, sellPrice = 55000,
          lcOffice = vec3(2549.66, 386.92, 108.62), blip = vec3(2556.73, 382.11, 108.62), garage = vec4(2588.82, 413.31, 108.46, 178.94), delivery = vec3(2560.19, 382.88, 108.62),
          lcCounters = { vec3(2556.73, 382.11, 108.62), vec3(2553.44, 386.16, 108.62) } },
        { id = "market_4", type = "247store", buyPrice = 180000, sellPrice = 90000,
          lcOffice = vec3(1159.86, -315.44, 69.21), blip = vec3(1163.42, -322.91, 69.20), garage = vec4(1155.32, -336.20, 68.35, 188.49), delivery = vec3(1154.82, -326.77, 69.21),
          lcCounters = { vec3(1163.43, -322.92, 69.21), vec3(1157.64, -321.53, 69.21) } },
        { id = "market_5", type = "247store", buyPrice = 130000, sellPrice = 65000,
          lcOffice = vec3(-1827.97, 798.20, 138.18), blip = vec3(-1820.92, 793.17, 138.11), garage = vec4(-1821.48, 777.52, 137.43, 216.69), delivery = vec3(-1826.26, 785.52, 138.28),
          lcCounters = { vec3(-1820.93, 793.17, 138.11), vec3(-1826.74, 791.42, 138.23) } },
        { id = "market_6", type = "247store", buyPrice = 150000, sellPrice = 75000,
          lcOffice = vec3(380.20, 332.71, 103.57), blip = vec3(374.20, 326.91, 103.56), garage = vec4(366.43, 332.03, 103.51, 165.15), delivery = vec3(379.77, 324.36, 103.57),
          lcCounters = { vec3(374.21, 326.92, 103.57), vec3(378.62, 329.68, 103.57) } },
        { id = "market_7", type = "247store", buyPrice = 120000, sellPrice = 60000,
          lcOffice = vec3(-3249.69, 1006.50, 12.83), blip = vec3(-3242.96, 1001.31, 12.83), garage = vec4(-3243.39, 991.74, 12.48, 272.72), delivery = vec3(-3240.70, 1007.29, 12.83),
          lcCounters = { vec3(-3242.96, 1001.32, 12.83), vec3(-3246.51, 1005.45, 12.83) } },
        { id = "market_8", type = "247store", buyPrice = 70000, sellPrice = 35000,
          lcOffice = vec3(1736.39, 6419.72, 35.04), blip = vec3(1729.38, 6415.42, 35.03), garage = vec4(1718.27, 6418.38, 33.45, 152.26), delivery = vec3(1734.04, 6411.11, 35.04),
          lcCounters = { vec3(1729.38, 6415.43, 35.04), vec3(1734.65, 6417.05, 35.04) } },
        { id = "market_9", type = "247store", buyPrice = 130000, sellPrice = 65000,
          lcOffice = vec3(544.38, 2662.86, 42.16), blip = vec3(547.74, 2671.56, 42.15), garage = vec4(533.90, 2667.90, 42.28, 8.76), delivery = vec3(541.56, 2674.03, 42.17),
          lcCounters = { vec3(547.75, 2671.56, 42.16), vec3(545.19, 2666.61, 42.16) } },
        { id = "market_10", type = "247store", buyPrice = 120000, sellPrice = 60000,
          lcOffice = vec3(1961.18, 3749.83, 32.34), blip = vec3(1961.35, 3741.49, 32.34), garage = vec4(1972.04, 3746.88, 32.32, 209.52), delivery = vec3(1967.00, 3742.92, 32.34),
          lcCounters = { vec3(1961.35, 3741.49, 32.34), vec3(1962.28, 3746.69, 32.34) } },
        { id = "market_11", type = "247store", buyPrice = 120000, sellPrice = 60000,
          lcOffice = vec3(2673.94, 3288.40, 55.24), blip = vec3(2679.80, 3286.73, 55.24), garage = vec4(2689.24, 3272.53, 55.25, 328.87), delivery = vec3(2679.74, 3276.63, 55.41),
          lcCounters = { vec3(2679.81, 3286.73, 55.24), vec3(2680.97, 3285.21, 55.24) } },
        { id = "market_12", type = "247store", buyPrice = 70000, sellPrice = 35000,
          lcOffice = vec3(1706.81, 4921.12, 42.06), blip = vec3(1700.00, 4925.55, 42.06), garage = vec4(1689.02, 4919.69, 42.08, 57.01), delivery = vec3(1700.31, 4932.72, 42.08),
          lcCounters = { vec3(1700.01, 4925.55, 42.06), vec3(1706.27, 4930.00, 42.06) } },
        { id = "market_13", type = "247store", buyPrice = 240000, sellPrice = 120000,
          lcOffice = vec3(-44.31, -1749.68, 29.42), blip = vec3(-50.81, -1754.87, 29.42), garage = vec4(-63.10, -1742.70, 29.31, 57.20), delivery = vec3(-55.72, -1755.53, 29.44),
          lcCounters = { vec3(-50.81, -1754.88, 29.42), vec3(-51.96, -1751.55, 29.42) } },
        { id = "market_14", type = "247store", buyPrice = 120000, sellPrice = 60000,
          lcOffice = vec3(1395.46, 3607.17, 34.98), blip = vec3(1398.45, 3607.05, 34.98), garage = vec4(1384.52, 3593.70, 34.90, 210.34), delivery = vec3(1391.90, 3598.45, 35.03),
          lcCounters = { vec3(1398.46, 3607.05, 34.98), vec3(1389.31, 3602.60, 34.98) } },
        { id = "market_15", type = "247store", buyPrice = 110000, sellPrice = 45000,
          lcOffice = vec3(-3048.32, 587.68, 7.91), blip = vec3(-3041.66, 586.27, 7.90), garage = vec4(-3045.94, 598.67, 7.49, 287.24), delivery = vec3(-3038.26, 593.59, 7.82),
          lcCounters = { vec3(-3041.66, 586.27, 7.91), vec3(-3042.83, 591.28, 7.91) } },
        { id = "market_16", type = "247store", buyPrice = 130000, sellPrice = 65000,
          lcOffice = vec3(1163.92, 2709.17, 38.16), blip = vec3(1164.06, 2707.60, 38.15), garage = vec4(1169.43, 2694.08, 37.84, 85.41), delivery = vec3(1160.22, 2702.11, 38.18),
          lcCounters = { vec3(1164.07, 2707.60, 38.16), vec3(1166.13, 2707.25, 38.16) } },
        { id = "market_17", type = "247store", buyPrice = 70000, sellPrice = 35000,
          lcOffice = vec3(-669.79, 5833.76, 17.33), blip = vec3(-677.68, 5839.18, 17.33), garage = vec4(-665.90, 5825.51, 17.34, 96.71), delivery = vec3(-678.53, 5833.06, 17.33),
          lcCounters = { vec3(-677.69, 5839.18, 17.33), vec3(-676.69, 5837.32, 17.33) } },
        { id = "market_18", type = "247store", buyPrice = 70000, sellPrice = 35000,
          lcOffice = vec3(169.27, 6644.16, 31.71), blip = vec3(164.15, 6641.15, 31.71), garage = vec4(146.90, 6634.98, 31.61, 175.81), delivery = vec3(157.06, 6641.22, 31.61),
          lcCounters = { vec3(164.16, 6641.16, 31.71), vec3(167.01, 6637.49, 31.71) } },
    },
}
