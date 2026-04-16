using System.Text.Json;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace FrontendApp.Pages;

public class ProductsModel : PageModel
{
    private readonly IHttpClientFactory _http;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNameCaseInsensitive = true };

    public List<ProductDto> Products { get; set; } = new();
    public string? ErrorMessage { get; set; }

    public ProductsModel(IHttpClientFactory http) => _http = http;

    public async Task OnGetAsync()
    {
        try
        {
            var client = _http.CreateClient("BackendApi");
            var response = await client.GetAsync("/api/products");
            response.EnsureSuccessStatusCode();
            var json = await response.Content.ReadAsStringAsync();
            Products = JsonSerializer.Deserialize<List<ProductDto>>(json, JsonOpts) ?? new();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }
}
