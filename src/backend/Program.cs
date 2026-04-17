// ============================================================================
// Backend API — Dual-Database Architecture
// ============================================================================
//  This API connects to TWO databases to demonstrate PaaS vs IaaS monitoring:
//
//  Frontend (Razor Pages)
//      │
//      ▼ HTTP calls
//  Backend API (.NET 8 Minimal API)    ← this file
//      │
//      ├──► Azure SQL PaaS (AdventureWorksLT)    ← ConnectionStrings:DefaultConnection
//      │    /api/products, /api/customers,           SQL auth (User ID + Password)
//      │    /api/orders, /api/categories
//      │
//      └──► SQL Server VM (AdventureWorks2022)   ← ConnectionStrings:SqlVmConnection
//           /api/vm/employees, /api/vm/departments   SQL auth via VM public IP:1433
// ============================================================================

using Microsoft.Data.SqlClient;
using Microsoft.ApplicationInsights;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
builder.Services.AddCors(options =>
{
    var origins = builder.Configuration["ALLOWED_ORIGINS"]?
        .Split(';', StringSplitOptions.RemoveEmptyEntries) ?? [];
    options.AddDefaultPolicy(policy =>
    {
        if (origins.Length > 0)
            policy.WithOrigins(origins).AllowAnyMethod().AllowAnyHeader();
        else
            policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader();
    });
});

var app = builder.Build();
app.UseCors();

// Health check endpoint
app.MapGet("/api/health", (IConfiguration config) =>
{
    var connStr = config.GetConnectionString("DefaultConnection");
    return Results.Ok(new
    {
        status = "healthy",
        timestamp = DateTime.UtcNow,
        databaseConfigured = !string.IsNullOrEmpty(connStr)
    });
});

// Get all products from AdventureWorksLT
app.MapGet("/api/products", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var products = new List<object>();
        await using var conn = new SqlConnection(config.GetConnectionString("DefaultConnection"));
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(
            "SELECT TOP 50 ProductID, Name, ProductNumber, Color, StandardCost, ListPrice, Size, Weight FROM SalesLT.Product ORDER BY Name", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            products.Add(new
            {
                productId = reader.GetInt32(0),
                name = reader.GetString(1),
                productNumber = reader.GetString(2),
                color = reader.IsDBNull(3) ? null : reader.GetString(3),
                standardCost = reader.GetDecimal(4),
                listPrice = reader.GetDecimal(5),
                size = reader.IsDBNull(6) ? null : reader.GetString(6),
                weight = reader.IsDBNull(7) ? (decimal?)null : reader.GetDecimal(7)
            });
        }
        return Results.Ok(products);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch products");
        return Results.Problem("Failed to fetch products from database.", statusCode: 500);
    }
});

// Get product categories
app.MapGet("/api/categories", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var categories = new List<object>();
        await using var conn = new SqlConnection(config.GetConnectionString("DefaultConnection"));
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(
            "SELECT ProductCategoryID, Name FROM SalesLT.ProductCategory ORDER BY Name", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            categories.Add(new
            {
                categoryId = reader.GetInt32(0),
                name = reader.GetString(1)
            });
        }
        return Results.Ok(categories);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch categories");
        return Results.Problem("Failed to fetch categories from database.", statusCode: 500);
    }
});

// Get customers
app.MapGet("/api/customers", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var customers = new List<object>();
        await using var conn = new SqlConnection(config.GetConnectionString("DefaultConnection"));
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(
            "SELECT TOP 50 CustomerID, FirstName, LastName, EmailAddress, CompanyName FROM SalesLT.Customer ORDER BY LastName", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            customers.Add(new
            {
                customerId = reader.GetInt32(0),
                firstName = reader.GetString(1),
                lastName = reader.GetString(2),
                email = reader.IsDBNull(3) ? null : reader.GetString(3),
                company = reader.IsDBNull(4) ? null : reader.GetString(4)
            });
        }
        return Results.Ok(customers);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch customers");
        return Results.Problem("Failed to fetch customers from database.", statusCode: 500);
    }
});

// Get sales orders
app.MapGet("/api/orders", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var orders = new List<object>();
        await using var conn = new SqlConnection(config.GetConnectionString("DefaultConnection"));
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP 50 h.SalesOrderID, h.OrderDate, h.TotalDue, h.Status,
                   c.FirstName + ' ' + c.LastName AS CustomerName
            FROM SalesLT.SalesOrderHeader h
            JOIN SalesLT.Customer c ON h.CustomerID = c.CustomerID
            ORDER BY h.OrderDate DESC", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            orders.Add(new
            {
                orderId = reader.GetInt32(0),
                orderDate = reader.GetDateTime(1),
                totalDue = reader.GetDecimal(2),
                status = reader.GetByte(3),
                customerName = reader.GetString(4)
            });
        }
        return Results.Ok(orders);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch orders");
        return Results.Problem("Failed to fetch orders from database.", statusCode: 500);
    }
});

// ============================================================================
// SQL VM (IaaS) endpoints — AdventureWorks2022 (full database)
// ============================================================================

// Get employees from SQL VM (HumanResources.Employee + Person.Person)
app.MapGet("/api/vm/employees", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var connStr = config.GetConnectionString("SqlVmConnection");
        if (string.IsNullOrEmpty(connStr))
            return Results.Problem("SQL VM connection string not configured.", statusCode: 503);

        var employees = new List<object>();
        await using var conn = new SqlConnection(connStr);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(@"
            SELECT TOP 50 e.BusinessEntityID, p.FirstName, p.LastName, e.JobTitle, e.HireDate, d.Name AS Department
            FROM HumanResources.Employee e
            JOIN Person.Person p ON e.BusinessEntityID = p.BusinessEntityID
            JOIN HumanResources.EmployeeDepartmentHistory edh ON e.BusinessEntityID = edh.BusinessEntityID
            JOIN HumanResources.Department d ON edh.DepartmentID = d.DepartmentID
            WHERE edh.EndDate IS NULL
            ORDER BY p.LastName", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            employees.Add(new
            {
                employeeId = reader.GetInt32(0),
                firstName = reader.GetString(1),
                lastName = reader.GetString(2),
                jobTitle = reader.GetString(3),
                hireDate = reader.GetDateTime(4),
                department = reader.GetString(5)
            });
        }
        return Results.Ok(employees);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch employees from SQL VM");
        return Results.Problem("Failed to fetch employees from SQL VM.", statusCode: 500);
    }
});

// Get departments from SQL VM
app.MapGet("/api/vm/departments", async (IConfiguration config, ILogger<Program> logger) =>
{
    try
    {
        var connStr = config.GetConnectionString("SqlVmConnection");
        if (string.IsNullOrEmpty(connStr))
            return Results.Problem("SQL VM connection string not configured.", statusCode: 503);

        var departments = new List<object>();
        await using var conn = new SqlConnection(connStr);
        await conn.OpenAsync();
        await using var cmd = new SqlCommand(@"
            SELECT d.DepartmentID, d.Name, d.GroupName,
                   COUNT(edh.BusinessEntityID) AS EmployeeCount
            FROM HumanResources.Department d
            LEFT JOIN HumanResources.EmployeeDepartmentHistory edh ON d.DepartmentID = edh.DepartmentID AND edh.EndDate IS NULL
            GROUP BY d.DepartmentID, d.Name, d.GroupName
            ORDER BY d.Name", conn);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            departments.Add(new
            {
                departmentId = reader.GetInt16(0),
                name = reader.GetString(1),
                groupName = reader.GetString(2),
                employeeCount = reader.GetInt32(3)
            });
        }
        return Results.Ok(departments);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to fetch departments from SQL VM");
        return Results.Problem("Failed to fetch departments from SQL VM.", statusCode: 500);
    }
});

// VM health check
app.MapGet("/api/vm/health", async (IConfiguration config, ILogger<Program> logger) =>
{
    var connStr = config.GetConnectionString("SqlVmConnection");
    if (string.IsNullOrEmpty(connStr))
        return Results.Ok(new { status = "not_configured", database = "SqlVm" });

    try
    {
        await using var conn = new SqlConnection(connStr);
        await conn.OpenAsync();
        return Results.Ok(new { status = "healthy", database = "SqlVm", timestamp = DateTime.UtcNow });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "SQL VM health check failed");
        return Results.Ok(new { status = "unhealthy", database = "SqlVm", error = ex.Message });
    }
});

app.Run();
