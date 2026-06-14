IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NULL
   OR OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam menu_position_likes.sql, bo tabela dbo.MenuPositions albo dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.MenuPositions', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.MenuPositionLikes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MenuPositionLikes (
        menu_position_like_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        position_id INT NOT NULL,
        user_id INT NOT NULL,
        created_at DATETIME2 NOT NULL
            CONSTRAINT DF_MenuPositionLikes_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_MenuPositionLikes_MenuPositions
            FOREIGN KEY (position_id) REFERENCES dbo.MenuPositions (position_id),
        CONSTRAINT FK_MenuPositionLikes_Users
            FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id),
        CONSTRAINT UQ_MenuPositionLikes_position_user
            UNIQUE (position_id, user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.MenuPositionLikes', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_MenuPositionLikes_position_id'
      AND object_id = OBJECT_ID(N'dbo.MenuPositionLikes')
)
BEGIN
    CREATE INDEX IX_MenuPositionLikes_position_id
        ON dbo.MenuPositionLikes (position_id);
END;
GO

IF OBJECT_ID(N'dbo.MenuPositionLikes', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_MenuPositionLikes_user_id'
      AND object_id = OBJECT_ID(N'dbo.MenuPositionLikes')
)
BEGIN
    CREATE INDEX IX_MenuPositionLikes_user_id
        ON dbo.MenuPositionLikes (user_id);
END;
GO
