using Microsoft.Data.SqlClient;
using Microsoft.ApplicationInsights;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddApplicationInsightsTelemetry();
builder.Services.AddCors(options =>
    options.AddDefaultPolicy(policy => policy.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader()));

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

app.Run();
