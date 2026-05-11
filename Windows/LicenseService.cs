using System.Security.Cryptography;
using System.Text;

namespace justQuit.Windows;

public sealed record LicenseValidationResult(bool IsValid, string Message);

public static class LicenseService
{
    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const byte ProductCode = 2;
    private const byte EditionCode = 1;
    private const string SigningSecret = "justquit-pro-license-secret";
    private static readonly DateOnly Epoch = new(2024, 1, 1);

    public static LicenseValidationResult Validate(string licenseKey)
    {
        if (string.IsNullOrWhiteSpace(licenseKey))
        {
            return new LicenseValidationResult(false, "Activate justQuit Pro to unlock countdowns, confirmation, and profiles.");
        }

        var normalized = new string((licenseKey ?? string.Empty)
            .ToUpperInvariant()
            .Where(Alphabet.Contains)
            .ToArray());

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

        return new LicenseValidationResult(true, "justQuit Pro is active.");
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
}
