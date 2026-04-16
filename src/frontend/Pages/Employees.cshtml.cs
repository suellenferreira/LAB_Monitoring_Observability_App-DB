using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class EmployeesModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public List<EmployeeDto> Employees { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public EmployeesModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        try
        {
            var client = _http.CreateClient("BackendApi");
            var response = await client.GetAsync("/api/vm/employees");
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            Employees = JsonSerializer.Deserialize<List<EmployeeDto>>(json, JsonOpts) ?? new();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}

public class EmployeeDto
{
    public int EmployeeId { get; set; }
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string JobTitle { get; set; } = "";
    public DateTime HireDate { get; set; }
    public string Department { get; set; } = "";
}
