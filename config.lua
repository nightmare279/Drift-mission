Config = {}

Config.NpcModel = "cs_fabien"
--Config.NpcModel = "s_m_m_dockwork_01"
Config.NpcCoords = vector3(237.0561, -753.9972, 34.6383)
Config.NpcHeading = 333.0

Config.DebugZone = true

Config.Missions = {

    [1] = {
        Name = "Legion Park Garage",
        Description = "This is a small garage area in Legion Park. Perfect for practicing your drift skills without leaving the city. Watch out for the walls! Lets see what you got!",
        Type = "drift", -- drift or sprint
        -- Example polygon zone (Maze Bank Arena style, edit as needed)
        Zone = {
            poly = {
                -- List of {x, y, z} points (clockwise/counterclockwise)
                vector3(160.5878, -753.8578, 33.1332),
                vector3(86.5002, -727.9178, 33.1334),
                vector3(101.3571, -688.1944, 33.3145),
                vector3(138.6172, -701.0850, 33.3224),
                vector3(148.6499, -674.3917, 33.3225),
                vector3(186.5848, -688.1983, 33.3225),
            },
            minZ = 29.0,
            maxZ = 36.0,
        },
        MissionTime = 80,
        RewardPerScore = 0.17,
        UnlockScore = 0,
        BlipSprite = 398,
        BlipColor = 1,
        -- Police dispatch chances
        PoliceOnCrash = 0.10,    -- 20% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.12,  -- 12% chance to trigger dispatch on spinout
    },
    [2] = {
        Name = "Hawick Ave zone",
        Description = "Hawick ave is a small area around a city block. Carefull not to leave the zone. Best of luck!",
        Type = "drift", -- drift or sprint
        -- Simple circle
        Zone = {
            center = vector3(-483.6001, -55.9839, 39.9943),
            radius = 100.0,
        },
        MissionTime = 60,
        RewardPerScore = 0.25,
        UnlockScore = 3500,
        BlipSprite = 398,
        BlipColor = 1,
        -- Police dispatch chances
        PoliceOnCrash = 0.25,    -- 15% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.18,  -- 8% chance to trigger dispatch on spinout
    },
        [3] = {
        Name = "Airport Terminal",
        Description = "Get ready to drift around the airport terminal! This area has wide open spaces and tight corners, perfect for showing off your skills. Just watch out for the poles!!",
        Type = "drift", -- drift or sprint
        -- Simple circle
        Zone = {
            center = vector3(-941.3202, -2579.5339, 13.9236),
            radius = 200.0,
        },
        MissionTime = 60,
        RewardPerScore = 0.25,
        UnlockScore = 5000,
        BlipSprite = 398,
        BlipColor = 1,
        -- Police dispatch chances
        PoliceOnCrash = 0.35,    -- 15% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.28,  -- 8% chance to trigger dispatch on spinout
    },
    [4] = {
        Name = "Police Blitz",
        Description = "Lets see how fast you can get away from the cops! This sprint style Drift Run will take you Near the police station, testing your speed and control. Watch out for 12!",
        Type = "sprint", -- new mission type
        StartingPosition = vector4(175.2536, -793.5472, 31.3595, 157.4504), -- Starting on South Park Way facing north
        InitialTime = 15, -- seconds to reach first checkpoint
        OutOfZoneAngle = 360, -- degrees - if player is more than this away from next checkpoint direction, consider out of zone
        Checkpoints = {
            [1] = {
                position = vector4(120.1423, -966.0762, 28.7910, 160.8403), -- East on South Park Way
                timeBonus = 5, -- seconds added when reached
                blipSprite = 1,
                blipColor = 5,
            },
            [2] = {
                position = vector4(126.5521, -1008.5294, 28.6936, 248.7461), -- North on Power Street heading south
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [3] = {
                position = vector4(200.5200, -1035.2136, 28.6579, 251.5851), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [4] = {
                position = vector4(230.4360, -1022.4668, 29.3575, 338.7439), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [5] = {
                position = vector4(252.2970, -962.6277, 28.9218, 338.4598), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [6] = {
                position = vector4(272.4377, -951.7962, 28.9969, 269.6627), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [7] = {
                position = vector4(388.1587, -955.1688, 28.9256, 267.2932), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [8] = {
                position = vector4(399.7945, -967.2504, 29.0077, 182.2086), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [9] = {
                position = vector4(397.3603, -1029.8757, 29.0822, 166.5322), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [10] = {
                position = vector4(371.2844, -1049.4727, 28.8777, 89.9407), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
        },
        FinishPosition = vector4(311.1362, -1049.3800, 28.8226, 89.8803), -- Back to start (full lap)
        FlareDistance = 20.0, -- distance between left and right flares
        CheckpointTriggerDistance = 25.0, -- distance to trigger checkpoint
        RewardPerScore = 0.08,
        UnlockScore = 9000,
        BlipSprite = 570, -- race flag
        BlipColor = 6, -- purple
        -- Police dispatch chances
        PoliceOnCrash = 0.75,    -- 25% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.55,  -- 15% chance to trigger dispatch on spinout
    },
    -- Add more missions here
}


--[[ 3 different missions for testing, this shows a example of how to set up each type of drift run

[1] = {
        Name = "Drift Mission I",
        Description = "Welcome to your first drift challenge! Navigate the circular drift zone and rack up points by maintaining controlled slides. Perfect for beginners to learn the basics of drift scoring.",
        Type = "drift", -- drift or sprint
        -- Simple circle
        Zone = {
            center = vector3(225.0042, -786.5714, 30.7387),
            radius = 29.0,
        },
        MissionTime = 60,
        RewardPerScore = 0.25,
        UnlockScore = 0,
        BlipSprite = 398,
        BlipColor = 1,
        -- Police dispatch chances
        PoliceOnCrash = 0.15,    -- 15% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.08,  -- 8% chance to trigger dispatch on spinout
    },
    [2] = {
        Name = "Drift Mission II",
        Description = "Step up to the advanced polygon course! This complex track layout will test your precision and control. Navigate tight corners and extended drift zones to maximize your score potential.",
        Type = "drift", -- drift or sprint
        -- Example polygon zone (Maze Bank Arena style, edit as needed)
        Zone = {
            poly = {
                -- List of {x, y, z} points (clockwise/counterclockwise)
                vector3(160.5878, -753.8578, 33.1332),
                vector3(86.5002, -727.9178, 33.1334),
                vector3(101.3571, -688.1944, 33.3145),
                vector3(138.6172, -701.0850, 33.3224),
                vector3(148.6499, -674.3917, 33.3225),
                vector3(186.5848, -688.1983, 33.3225),
            },
            minZ = 29.0,
            maxZ = 36.0,
        },
        MissionTime = 80,
        RewardPerScore = 0.17,
        UnlockScore = 3500,
        BlipSprite = 398,
        BlipColor = 1,
        -- Police dispatch chances
        PoliceOnCrash = 0.20,    -- 20% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.12,  -- 12% chance to trigger dispatch on spinout
    },
    [3] = {
        Name = "Legion Park Sprint",
        Description = "Test your drift skills with a quick lap around Legion Park! This training circuit will help you master the basics of sprint missions while staying close to the city center.",
        Type = "sprint", -- new mission type
        StartingPosition = vector4(175.2536, -793.5472, 31.3595, 157.4504), -- Starting on South Park Way facing north
        InitialTime = 30, -- seconds to reach first checkpoint
        OutOfZoneAngle = 360, -- degrees - if player is more than this away from next checkpoint direction, consider out of zone
        Checkpoints = {
            [1] = {
                position = vector4(120.1423, -966.0762, 28.7910, 160.8403), -- East on South Park Way
                timeBonus = 5, -- seconds added when reached
                blipSprite = 1,
                blipColor = 5,
            },
            [2] = {
                position = vector4(126.5521, -1008.5294, 28.6936, 248.7461), -- North on Power Street heading south
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [3] = {
                position = vector4(200.5200, -1035.2136, 28.6579, 251.5851), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
            [4] = {
                position = vector4(221.1239, -1065.0391, 28.4828, 170.7524), -- Back to start (full lap)
                timeBonus = 5,
                blipSprite = 1,
                blipColor = 5,
            },
        },
        FinishPosition = vector4(216.4853, -1123.2692, 28.6091, 176.3168), -- Back to start (full lap)
        FlareDistance = 20.0, -- distance between left and right flares
        CheckpointTriggerDistance = 25.0, -- distance to trigger checkpoint
        RewardPerScore = 0.08,
        UnlockScore = 5000,
        BlipSprite = 570, -- race flag
        BlipColor = 6, -- purple
        -- Police dispatch chances
        PoliceOnCrash = 0.25,    -- 25% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.15,  -- 15% chance to trigger dispatch on spinout
    }, 
    
    ]]