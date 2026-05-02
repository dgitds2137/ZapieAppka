IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam sessions.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.Sessions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Sessions (
        id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        user_id INT NOT NULL,
        session_token NVARCHAR(255) NOT NULL,
        created_at DATETIME2 NOT NULL
            CONSTRAINT DF_Sessions_created_at DEFAULT SYSUTCDATETIME(),
        last_seen_at DATETIME2 NOT NULL
            CONSTRAINT DF_Sessions_last_seen_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_Sessions_Users
            FOREIGN KEY (user_id) REFERENCES dbo.Users (user_id)
    );
END;
GO

IF OBJECT_ID(N'dbo.Sessions', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Sessions', N'created_at') IS NULL
BEGIN
    ALTER TABLE dbo.Sessions
        ADD created_at DATETIME2 NULL;

    EXEC sp_executesql N'
        UPDATE dbo.Sessions
        SET created_at = SYSUTCDATETIME()
        WHERE created_at IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.Sessions
            ALTER COLUMN created_at DATETIME2 NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.Sessions', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Sessions', N'last_seen_at') IS NULL
BEGIN
    ALTER TABLE dbo.Sessions
        ADD last_seen_at DATETIME2 NULL;

    EXEC sp_executesql N'
        UPDATE dbo.Sessions
        SET last_seen_at = created_at
        WHERE last_seen_at IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.Sessions
            ALTER COLUMN last_seen_at DATETIME2 NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.Sessions', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Sessions_user_id'
      AND object_id = OBJECT_ID(N'dbo.Sessions')
)
BEGIN
    CREATE INDEX IX_Sessions_user_id
        ON dbo.Sessions (user_id);
END;
GO

IF OBJECT_ID(N'dbo.Sessions', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Sessions_last_seen_at'
      AND object_id = OBJECT_ID(N'dbo.Sessions')
)
BEGIN
    CREATE INDEX IX_Sessions_last_seen_at
        ON dbo.Sessions (last_seen_at);
END;
GO
