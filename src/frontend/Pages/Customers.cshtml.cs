using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class CustomersModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public List<CustomerDto> Customers { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public CustomersModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        try
        {
            var client = _http.CreateClient("BackendApi");
            var response = await client.GetAsync("/api/customers");
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            Customers = JsonSerializer.Deserialize<List<CustomerDto>>(json, JsonOpts) ?? new();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}
