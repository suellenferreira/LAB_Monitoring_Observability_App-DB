using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class OrdersModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public List<OrderDto> Orders { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public OrdersModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        try
        {
            var client = _http.CreateClient("BackendApi");
            var response = await client.GetAsync("/api/orders");
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            Orders = JsonSerializer.Deserialize<List<OrderDto>>(json, JsonOpts) ?? new();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}
