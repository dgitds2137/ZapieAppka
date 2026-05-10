IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    PRINT N'Pomijam user_roles.sql, bo tabela dbo.Users jeszcze nie istnieje.';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'role') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD role NVARCHAR(50) NULL;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Users', N'loyalty_points') IS NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD loyalty_points INT NULL;

    EXEC sp_executesql N'
        UPDATE dbo.Users
        SET loyalty_points = 0
        WHERE loyalty_points IS NULL;
    ';

    EXEC sp_executesql N'
        ALTER TABLE dbo.Users
            ALTER COLUMN loyalty_points INT NOT NULL;
    ';
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    DECLARE @drop_check_sql NVARCHAR(MAX) = N'';

    SELECT @drop_check_sql = STRING_AGG(
        N'ALTER TABLE dbo.Users DROP CONSTRAINT ' + QUOTENAME(cc.name) + N';',
        CHAR(10)
    )
    FROM sys.check_constraints AS cc
    INNER JOIN sys.columns AS c
        ON c.object_id = cc.parent_object_id
       AND c.column_id = cc.parent_column_id
    WHERE cc.parent_object_id = OBJECT_ID(N'dbo.Users')
      AND c.name = N'role';

    IF @drop_check_sql IS NOT NULL AND @drop_check_sql <> N''
    BEGIN
        EXEC sp_executesql @drop_check_sql;
    END;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    DECLARE @drop_default_sql NVARCHAR(MAX) = N'';

    SELECT @drop_default_sql = STRING_AGG(
        N'ALTER TABLE dbo.Users DROP CONSTRAINT ' + QUOTENAME(dc.name) + N';',
        CHAR(10)
    )
    FROM sys.default_constraints AS dc
    INNER JOIN sys.columns AS c
        ON c.object_id = dc.parent_object_id
       AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.Users')
      AND c.name = N'role';

    IF @drop_default_sql IS NOT NULL AND @drop_default_sql <> N''
    BEGIN
        EXEC sp_executesql @drop_default_sql;
    END;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    UPDATE dbo.Users
    SET role = CASE
        WHEN role IS NULL OR LTRIM(RTRIM(role)) = N'' THEN N'user'
        WHEN LOWER(LTRIM(RTRIM(role))) = N'client' THEN N'user'
        WHEN LOWER(LTRIM(RTRIM(role))) IN (N'user', N'employee', N'driver', N'admin')
            THEN LOWER(LTRIM(RTRIM(role)))
        ELSE N'user'
    END;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD CONSTRAINT DF_Users_role DEFAULT N'user' FOR role;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM sys.default_constraints AS dc
    INNER JOIN sys.columns AS c
        ON c.object_id = dc.parent_object_id
       AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID(N'dbo.Users')
      AND c.name = N'loyalty_points'
)
BEGIN
    ALTER TABLE dbo.Users
        ADD CONSTRAINT DF_Users_loyalty_points DEFAULT (0) FOR loyalty_points;
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    ALTER TABLE dbo.Users
        ADD CONSTRAINT CK_Users_role
            CHECK (role IN (N'user', N'employee', N'driver', N'admin'));
END;
GO
