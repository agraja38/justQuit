using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace justQuit.Windows;

public sealed record LicenseValidationResult(bool IsValid, string Message, string? LicenseId = null);

public static class LicenseService
{
    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const byte ProductCode = 2;
    private const byte EditionCode = 1;
    private const string SigningSecret = "justquit-pro-license-secret";
    private const string ActivationUrl = "https://license-key-generator-api.onrender.com/v1/activate";
    private static readonly DateOnly Epoch = new(2024, 1, 1);
    private static readonly HttpClient HttpClient = new() { Timeout = TimeSpan.FromSeconds(20) };

    public static async Task<LicenseValidationResult> ActivateAsync(string licenseKey)
    {
        var localResult = Validate(licenseKey);
        if (!localResult.IsValid)
        {
            return localResult;
        }

        try
        {
            using var response = await HttpClient.PostAsync(
                ActivationUrl,
                new StringContent(
                    JsonSerializer.Serialize(new ActivationRequest(
                        NormalizeKey(licenseKey),
                        DeviceId(),
                        Environment.MachineName,
                        typeof(LicenseService).Assembly.GetName().Version?.ToString(3) ?? string.Empty)),
                    Encoding.UTF8,
                    "application/json"));

            var body = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                return new LicenseValidationResult(false, ServerErrorMessage(body));
            }

            var activation = JsonSerializer.Deserialize<ActivationResponse>(body);
            return new LicenseValidationResult(
                true,
                "justQuit Pro is active.",
                string.IsNullOrWhiteSpace(activation?.LicenseId) ? localResult.LicenseId : activation.LicenseId);
        }
        catch (Exception error)
        {
            return new LicenseValidationResult(false, $"Could not contact the license server. {error.Message}");
        }
    }

    public static LicenseValidationResult Validate(string licenseKey)
    {
        if (string.IsNullOrWhiteSpace(licenseKey))
        {
            return new LicenseValidationResult(false, "Activate justQuit Pro to unlock countdowns, confirmation, and profiles.");
        }

        var normalized = NormalizeKey(licenseKey);

        var decoded = DecodeBase32(normalized);
        if (decoded is null || decoded.Length != 22)
        {
            return new LicenseValidationResult(false, "Enter a valid justQuit Pro license key.");
        }

        var payload = decoded[..10];
        var signature = decoded[10..];

        if (payload[0] != ProductCode || payload[1] != EditionCode)
        {
            return new LicenseValidationResult(false, "This license is not for justQuit Pro.");
        }

        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(SigningSecret));
        var expectedSignature = hmac.ComputeHash(payload)[..12];
        if (!CryptographicOperations.FixedTimeEquals(signature, expectedSignature))
        {
            return new LicenseValidationResult(false, "The license signature could not be verified.");
        }

        var daysSinceEpoch = (payload[2] << 8) | payload[3];
        if (Epoch.AddDays(daysSinceEpoch) > DateOnly.FromDateTime(DateTime.UtcNow.AddDays(1)))
        {
            return new LicenseValidationResult(false, "This license has an invalid issue date.");
        }

        var licenseId = $"JQPRO-{EncodeBase32(payload[4..])}";
        return new LicenseValidationResult(true, "justQuit Pro is active.", licenseId);
    }

    private static string NormalizeKey(string licenseKey) => new((licenseKey ?? string.Empty)
        .ToUpperInvariant()
        .Where(Alphabet.Contains)
        .ToArray());

    private static string DeviceId()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "justQuit");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "license-device-id.txt");
        if (File.Exists(path))
        {
            var stored = File.ReadAllText(path).Trim();
            if (!string.IsNullOrWhiteSpace(stored))
            {
                return stored;
            }
        }

        var deviceId = Guid.NewGuid().ToString();
        File.WriteAllText(path, deviceId);
        return deviceId;
    }

    private static string ServerErrorMessage(string body)
    {
        try
        {
            var error = JsonSerializer.Deserialize<ActivationError>(body);
            return error?.Detail switch
            {
                "license_not_issued" => "This key was not found in the issued-license ledger.",
                string detail when detail.StartsWith("device_limit_reached", StringComparison.OrdinalIgnoreCase) => "This license key has already been activated on its allowed device limit.",
                string detail when !string.IsNullOrWhiteSpace(detail) => detail,
                _ => "The license server rejected this activation.",
            };
        }
        catch
        {
            return "The license server rejected this activation.";
        }
    }

    private static byte[]? DecodeBase32(string value)
    {
        var buffer = 0;
        var bitsInBuffer = 0;
        var output = new List<byte>();

        foreach (var character in value)
        {
            var index = Alphabet.IndexOf(character);
            if (index < 0) return null;

            buffer = (buffer << 5) | index;
            bitsInBuffer += 5;

            while (bitsInBuffer >= 8)
            {
                bitsInBuffer -= 8;
                output.Add((byte)((buffer >> bitsInBuffer) & 0xFF));
            }
        }

        return output.ToArray();
    }

    private static string EncodeBase32(byte[] data)
    {
        var buffer = 0;
        var bitsInBuffer = 0;
        var output = new StringBuilder();

        foreach (var value in data)
        {
            buffer = (buffer << 8) | value;
            bitsInBuffer += 8;

            while (bitsInBuffer >= 5)
            {
                bitsInBuffer -= 5;
                output.Append(Alphabet[(buffer >> bitsInBuffer) & 0b11111]);
            }
        }

        if (bitsInBuffer > 0)
        {
            output.Append(Alphabet[(buffer << (5 - bitsInBuffer)) & 0b11111]);
        }

        return output.ToString();
    }
}

internal sealed record ActivationRequest(
    [property: JsonPropertyName("license_key")] string LicenseKey,
    [property: JsonPropertyName("device_id")] string DeviceId,
    [property: JsonPropertyName("device_name")] string DeviceName,
    [property: JsonPropertyName("app_version")] string AppVersion);

internal sealed record ActivationResponse(
    [property: JsonPropertyName("license_id")] string LicenseId);

internal sealed record ActivationError(
    [property: JsonPropertyName("detail")] string Detail);
