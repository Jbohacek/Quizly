using System.Net;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc.Testing;
using Quizly.Tests.Infrastructure;
using Quizly.Web.Components;

namespace Quizly.Tests.Api;

/// <summary>The Blazor dashboard's cookie login (static server rendering + antiforgery) and logout.</summary>
public sealed partial class DashboardTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Anonymous_dashboard_redirects_to_login()
    {
        using var client = NoRedirects();

        var response = await client.GetAsync("/admin/obchod", Ct);

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.StartsWith("/admin/login", response.Headers.Location?.PathAndQuery, StringComparison.Ordinal);
        Assert.Contains("obchod", Uri.UnescapeDataString(response.Headers.Location!.Query), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Root_redirects_to_the_dashboard() =>
        Assert.Equal("/admin", (await NoRedirects().GetAsync("/", Ct)).Headers.Location?.OriginalString);

    [Fact]
    public async Task Login_form_sets_the_cookie_and_logout_clears_it()
    {
        using var client = NoRedirects();

        var login = await SubmitLoginAsync(client, QuizlyFactory.AdminUsername, QuizlyFactory.AdminPassword, "/admin/uzivatele");

        Assert.Equal(HttpStatusCode.Redirect, login.StatusCode);
        Assert.Equal("/admin/uzivatele", LocalTarget(login));
        var page = await client.GetAsync("/admin/uzivatele", Ct);
        Assert.Equal(HttpStatusCode.OK, page.StatusCode);
        Assert.Contains("Uživatelé", await TextAsync(page), StringComparison.Ordinal);

        // The sidebar form carries an antiforgery token; without it logout is refused.
        var withoutToken = await client.PostAsync("/admin/logout", new FormUrlEncodedContent([]), Ct);
        Assert.Equal(HttpStatusCode.BadRequest, withoutToken.StatusCode);

        var html = await page.Content.ReadAsStringAsync(Ct);
        var token = HiddenInputs(html)["__RequestVerificationToken"];
        var logout = await client.PostAsync("/admin/logout", new FormUrlEncodedContent([new("__RequestVerificationToken", token)]), Ct);
        Assert.Equal("/admin/login", LocalTarget(logout));
        Assert.Equal(HttpStatusCode.Redirect, (await client.GetAsync("/admin", Ct)).StatusCode);
    }

    [Fact]
    public async Task Wrong_password_shows_an_error_and_sets_no_cookie()
    {
        using var client = NoRedirects();

        var response = await SubmitLoginAsync(client, QuizlyFactory.AdminUsername, "wrong-password");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("Nesprávné uživatelské jméno nebo heslo.", await TextAsync(response), StringComparison.Ordinal);
        Assert.Equal(HttpStatusCode.Redirect, (await client.GetAsync("/admin", Ct)).StatusCode);
    }

    [Fact]
    public async Task Login_never_redirects_off_site()
    {
        using var client = NoRedirects();

        var response = await SubmitLoginAsync(client, QuizlyFactory.AdminUsername, QuizlyFactory.AdminPassword, "https://evil.example/admin");

        Assert.Equal("/admin", LocalTarget(response));
    }

    [Theory]
    [InlineData("/admin/balicky/3", "/admin/balicky/3")]
    [InlineData(null, "/admin")]
    [InlineData("https://evil.example", "/admin")]
    [InlineData("//evil.example/admin", "/admin")]
    [InlineData("/admin\\..\\x", "/admin")]
    [InlineData("/api/admin/users", "/admin")]
    public void Return_urls_stay_on_the_dashboard(string? input, string expected) =>
        Assert.Equal(expected, AdminDashboard.SafeReturnUrl(input));

    [Fact]
    public async Task App_tokens_do_not_open_the_dashboard()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var client = NoRedirects();
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", tokens.AccessToken);

        var response = await client.GetAsync("/admin", Ct);

        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
    }

    /// <summary>The redirect target's path; it must stay on this host (NavigateTo sends absolute URLs).</summary>
    private static string LocalTarget(HttpResponseMessage response)
    {
        var target = new Uri(new Uri("http://localhost"), response.Headers.Location!);
        Assert.Equal("localhost", target.Host);
        return target.PathAndQuery;
    }

    /// <summary>Response HTML with entities decoded (Czech letters are written as &amp;#x…;).</summary>
    private static async Task<string> TextAsync(HttpResponseMessage response) =>
        WebUtility.HtmlDecode(await response.Content.ReadAsStringAsync(Ct));

    private HttpClient NoRedirects() =>
        factory.CreateClient(new WebApplicationFactoryClientOptions { AllowAutoRedirect = false, HandleCookies = true });

    /// <summary>Loads the login page (antiforgery cookie + hidden fields) and posts the form like a browser.</summary>
    private static async Task<HttpResponseMessage> SubmitLoginAsync(HttpClient client, string username, string password, string? returnUrl = null)
    {
        var path = returnUrl is null ? "/admin/login" : $"/admin/login?returnUrl={Uri.EscapeDataString(returnUrl)}";
        var form = await client.GetStringAsync(path, Ct);
        var fields = HiddenInputs(form);
        fields["Model.Username"] = username;
        fields["Model.Password"] = password;
        return await client.PostAsync(path, new FormUrlEncodedContent(fields), Ct);
    }

    private static Dictionary<string, string> HiddenInputs(string html) =>
        HiddenInput().Matches(html).ToDictionary(m => m.Groups["name"].Value, m => WebUtility.HtmlDecode(m.Groups["value"].Value));

    [GeneratedRegex("<input type=\"hidden\" name=\"(?<name>[^\"]+)\" value=\"(?<value>[^\"]*)\"")]
    private static partial Regex HiddenInput();
}
