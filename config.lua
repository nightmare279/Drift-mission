Config = {}

Config.NpcModel = "s_m_m_dockwork_01"
Config.NpcCoords = vector3(237.0561, -753.9972, 34.6383)
Config.NpcHeading = 333.0

Config.DebugZone = true

Config.Missions = {
    [1] = {
        Name = "Drift Mission I",
        Description = "Welcome to your first drift challenge! Navigate the circular drift zone and rack up points by maintaining controlled slides. Perfect for beginners to learn the basics of drift scoring.",
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
        PoliceOnCrash = 0.99,    -- 15% chance to trigger dispatch on crash
        PoliceOnSpinout = 0.99,  -- 8% chance to trigger dispatch on spinout
    },
    [2] = {
        Name = "Drift Mission II",
        Description = "Step up to the advanced polygon course! This complex track layout will test your precision and control. Navigate tight corners and extended drift zones to maximize your score potential.",
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
    -- Add more missions!
}