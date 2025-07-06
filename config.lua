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
                vector3(120.5, -744.1, 32.1),
                vector3(146.4, -717.6, 32.1),
                vector3(161.2, -733.0, 32.1),
                vector3(136.7, -759.2, 32.1),
                vector3(120.5, -744.1, 32.1),
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
