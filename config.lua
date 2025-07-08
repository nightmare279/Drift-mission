Config = {}

Config.NpcModel = "s_m_m_dockwork_01"
Config.NpcCoords = vector3(237.0561, -753.9972, 34.6383)
Config.NpcHeading = 333.0

Config.DebugZone = true

Config.Missions = {
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
        OutOfZoneAngle = 150, -- degrees - if player is more than this away from next checkpoint direction, consider out of zone
        Checkpoints = {
            [1] = {
                position = vector4(161.7272, -833.7833, 31.1805, 161.1737), -- East on South Park Way
                timeBonus = 15, -- seconds added when reached
                blipSprite = 1,
                blipColor = 5,
            },
            [2] = {
                position = vector4(150.1861, -866.5803, 30.7429, 160.2843), -- North on Power Street heading south
                timeBonus = 15,
                blipSprite = 1,
                blipColor = 5,
            },
        },
        FinishPosition = vector4(134.0956, -909.3702, 30.1970, 159.0968), -- Back to start (full lap)
        FlareDistance = 8.0, -- distance between left and right flares
        CheckpointTriggerDistance = 12.0, -- distance to trigger checkpoint
        RewardPerScore = 0.30,
        UnlockScore = 5000,
        BlipSprite = 570, -- race flag
        BlipColor = 6, -- purple
        -- Police dispatch chances
        PoliceOnCrash = 0.25,    -- 25% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.15,  -- 15% chance to trigger dispatch on spinout
    },
    -- Add more missions here
}