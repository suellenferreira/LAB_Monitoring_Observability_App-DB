// Dashboard page model — fetches data from BOTH databases via Backend API:
//   PaaS endpoints:  /api/products, /api/customers, /api/orders, /api/categories
//   IaaS endpoints:  /api/vm/employees, /api/vm/departments

using System.Net.Http;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class IndexModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    // PaaS (AdventureWorksLT)
    public int ProductCount { get; set; }
    public int CustomerCount { get; set; }
    public int OrderCount { get; set; }
    public int CategoryCount { get; set; }
    public List<ProductDto> RecentProducts { get; set; } = new();
    public List<OrderDto> RecentOrders { get; set; } = new();
    public string? ErrorMessage { get; set; }

    // IaaS (AdventureWorks2022 on SQL VM)
    public int EmployeeCount { get; set; }
    public int DepartmentCount { get; set; }
    public List<EmployeeDto> RecentEmployees { get; set; } = new();
    public string? VmErrorMessage { get; set; }

    public IndexModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        var client = _http.CreateClient("BackendApi");

        // Fetch PaaS data
        try
        {
            var products = await FetchAsync<List<ProductDto>>(client, "/api/products") ?? new();
            var customers = await FetchAsync<List<CustomerDto>>(client, "/api/customers") ?? new();
            var orders = await FetchAsync<List<OrderDto>>(client, "/api/orders") ?? new();
            var categories = await FetchAsync<List<CategoryDto>>(client, "/api/categories") ?? new();

            ProductCount = products.Count;
            CustomerCount = customers.Count;
            OrderCount = orders.Count;
            CategoryCount = categories.Count;
            RecentProducts = products.Take(5).ToList();
            RecentOrders = orders.Take(5).ToList();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }

        // Fetch IaaS (SQL VM) data
        try
        {
            var employees = await FetchAsync<List<EmployeeDto>>(client, "/api/vm/employees") ?? new();
            var departments = await FetchAsync<List<DepartmentDto>>(client, "/api/vm/departments") ?? new();

            EmployeeCount = employees.Count;
            DepartmentCount = departments.Count;
            RecentEmployees = employees.Take(5).ToList();
        }
        catch (Exception ex)
        {
            VmErrorMessage = ex.Message;
        }
    }

    private static async Task<T?> FetchAsync<T>(HttpClient client, string url)
    {
        var response = await client.GetAsync(url);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(json, JsonOpts);
    }
}

public class ProductDto
{
    public int ProductId { get; set; }
    public string Name { get; set; } = "";
    public string ProductNumber { get; set; } = "";
    public string? Color { get; set; }
    public decimal StandardCost { get; set; }
    public decimal ListPrice { get; set; }
    public string? Size { get; set; }
    public decimal? Weight { get; set; }
}

public class CustomerDto
{
    public int CustomerId { get; set; }
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string? Email { get; set; }
    public string? Company { get; set; }
}

public class OrderDto
{
    public int OrderId { get; set; }
    public DateTime OrderDate { get; set; }
    public decimal TotalDue { get; set; }
    public int Status { get; set; }
    public string CustomerName { get; set; } = "";
}

public class CategoryDto
{
    public int CategoryId { get; set; }
    public string Name { get; set; } = "";
}
