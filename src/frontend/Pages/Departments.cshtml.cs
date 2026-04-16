using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class DepartmentsModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public List<DepartmentDto> Departments { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public DepartmentsModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        try
        {
            var client = _http.CreateClient("BackendApi");
            var response = await client.GetAsync("/api/vm/departments");
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            Departments = JsonSerializer.Deserialize<List<DepartmentDto>>(json, JsonOpts) ?? new();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}

public class DepartmentDto
{
    public int DepartmentId { get; set; }
    public string Name { get; set; } = "";
    public string GroupName { get; set; } = "";
    public int EmployeeCount { get; set; }
}
