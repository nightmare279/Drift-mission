Config = {}

Config.NpcModel = "s_m_m_dockwork_01"
Config.NpcCoords = vector3(237.0561, -753.9972, 34.6383)
Config.NpcHeading = 333.0

Config.DebugZone = true

Config.Missions = {
    [1] = {
        Name = "Drift Mission I",
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
    },
    [2] = {
        Name = "Drift Mission II",
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
    },
    -- Add more missions!
}
