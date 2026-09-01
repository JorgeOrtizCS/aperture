using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Newtonsoft.Json;

namespace Aperture_Desktop_Client.Services
{
    public class ApiClient
    {
        private readonly HttpClient _httpClient;

        public string Token
        {
            get;
            private set;
        }

        public ApiClient(string baseUrl)
        {
            _httpClient = new HttpClient();

            _httpClient.BaseAddress =
                new Uri(baseUrl);

            _httpClient.Timeout =
                TimeSpan.FromSeconds(30);
        }

        public void SetToken(string token)
        {
            Token = token;

            _httpClient.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue(
                    "Bearer",
                    token);
        }

        public void ClearToken()
        {
            Token = null;

            _httpClient.DefaultRequestHeaders.Authorization =
                null;
        }

        public async Task<TResponse> PostAsync<TRequest, TResponse>(
            string endpoint,
            TRequest request)
        {
            string json =
                JsonConvert.SerializeObject(request);

            try
            {
                using (var content =
                    new StringContent(
                        json,
                        Encoding.UTF8,
                        "application/json"))
                {
                    HttpResponseMessage response =
                        await _httpClient.PostAsync(
                            endpoint,
                            content);

                    string responseJson =
                        await response.Content
                            .ReadAsStringAsync();

                    if (!response.IsSuccessStatusCode)
                    {
                        throw new Exception(
                            "API returned an error.\r\n\r\n" +
                            "HTTP Status: " +
                            (int)response.StatusCode +
                            " " +
                            response.ReasonPhrase +
                            "\r\n\r\n" +
                            "URL: " +
                            _httpClient.BaseAddress +
                            endpoint +
                            "\r\n\r\n" +
                            "Response:\r\n" +
                            responseJson);
                    }

                    try
                    {
                        return JsonConvert
                            .DeserializeObject<TResponse>(
                                responseJson);
                    }
                    catch (Exception ex)
                    {
                        throw new Exception(
                            "The API responded successfully, " +
                            "but the response could not be " +
                            "deserialized.\r\n\r\n" +
                            "URL: " +
                            _httpClient.BaseAddress +
                            endpoint +
                            "\r\n\r\n" +
                            "Response:\r\n" +
                            responseJson +
                            "\r\n\r\n" +
                            "Deserialization error:\r\n" +
                            ex.Message,
                            ex);
                    }
                }
            }
            catch (HttpRequestException ex)
            {
                throw new Exception(
                    "Could not connect to the Web API.\r\n\r\n" +
                    "URL: " +
                    _httpClient.BaseAddress +
                    endpoint +
                    "\r\n\r\n" +
                    "Error:\r\n" +
                    ex.Message,
                    ex);
            }
        }

        public async Task<TResponse> GetAsync<TResponse>(
            string endpoint)
        {
            try
            {
                HttpResponseMessage response =
                    await _httpClient.GetAsync(endpoint);

                string responseJson =
                    await response.Content
                        .ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    throw new Exception(
                        "API returned an error.\r\n\r\n" +
                        "HTTP Status: " +
                        (int)response.StatusCode +
                        " " +
                        response.ReasonPhrase +
                        "\r\n\r\n" +
                        "URL: " +
                        _httpClient.BaseAddress +
                        endpoint +
                        "\r\n\r\n" +
                        "Response:\r\n" +
                        responseJson);
                }

                return JsonConvert
                    .DeserializeObject<TResponse>(
                        responseJson);
            }
            catch (HttpRequestException ex)
            {
                throw new Exception(
                    "Could not connect to the Web API.\r\n\r\n" +
                    "URL: " +
                    _httpClient.BaseAddress +
                    endpoint +
                    "\r\n\r\n" +
                    "Error:\r\n" +
                    ex.Message,
                    ex);
            }
        }

        public async Task PostAsync(
            string endpoint)
        {
            try
            {
                HttpResponseMessage response =
                    await _httpClient.PostAsync(
                        endpoint,
                        null);

                string responseJson =
                    await response.Content
                        .ReadAsStringAsync();

                if (!response.IsSuccessStatusCode)
                {
                    throw new Exception(
                        "API returned an error.\r\n\r\n" +
                        "HTTP Status: " +
                        (int)response.StatusCode +
                        " " +
                        response.ReasonPhrase +
                        "\r\n\r\n" +
                        "URL: " +
                        _httpClient.BaseAddress +
                        endpoint +
                        "\r\n\r\n" +
                        "Response:\r\n" +
                        responseJson);
                }
            }
            catch (HttpRequestException ex)
            {
                throw new Exception(
                    "Could not connect to the Web API.\r\n\r\n" +
                    "URL: " +
                    _httpClient.BaseAddress +
                    endpoint +
                    "\r\n\r\n" +
                    "Error:\r\n" +
                    ex.Message,
                    ex);
            }
        }
    }
}
