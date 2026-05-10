IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
   AND NOT EXISTS (
    SELECT 1
    FROM dbo.Users
    WHERE LOWER(LTRIM(RTRIM(email))) = N'demo@zapieapp.pl'
)
BEGIN
    INSERT INTO dbo.Users (
        name,
        email,
        password,
        phone,
        role,
        loyalty_points,
        created_at
    )
    VALUES (
        N'Demo',
        N'demo@zapieapp.pl',
        N'$2b$12$LOor.5gOCwHR2LBfLI3yrehhfOAbgUUSslp.slwlITgI7uGnSgTAi',
        NULL,
        N'user',
        0,
        SYSUTCDATETIME()
    );
END;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    UPDATE dbo.Users
    SET
        name = COALESCE(NULLIF(LTRIM(RTRIM(name)), N''), N'Demo'),
        role = N'user',
        loyalty_points = COALESCE(loyalty_points, 0)
    WHERE LOWER(LTRIM(RTRIM(email))) = N'demo@zapieapp.pl';
END;
GO
