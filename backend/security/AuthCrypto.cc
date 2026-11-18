#include "AuthCrypto.h"

#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/hmac.h>
#include <openssl/rand.h>
#include <json/json.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <memory>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace taskmanager::security
{
namespace
{
constexpr std::uint64_t kScryptN = 1U << 15;
constexpr std::uint64_t kScryptR = 8;
constexpr std::uint64_t kScryptP = 1;
constexpr std::uint64_t kScryptMaxMemory = 64U * 1024U * 1024U;
constexpr std::size_t kScryptSaltBytes = 16;
constexpr std::size_t kScryptKeyBytes = 32;
constexpr std::size_t kMaxPasswordBytes = 1024;
constexpr std::int64_t kMaxAccessLifetimeSeconds = 15 * 60;
constexpr char kBase64UrlAlphabet[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

std::string base64UrlEncode(const unsigned char *data, std::size_t length)
{
    std::string result;
    result.reserve((length * 4 + 2) / 3);
    for (std::size_t i = 0; i < length; i += 3)
    {
        const std::size_t remaining = length - i;
        const unsigned int block =
            (static_cast<unsigned int>(data[i]) << 16) |
            (remaining > 1 ? static_cast<unsigned int>(data[i + 1]) << 8 : 0) |
            (remaining > 2 ? static_cast<unsigned int>(data[i + 2]) : 0);
        result.push_back(kBase64UrlAlphabet[(block >> 18) & 0x3f]);
        result.push_back(kBase64UrlAlphabet[(block >> 12) & 0x3f]);
        if (remaining > 1)
        {
            result.push_back(kBase64UrlAlphabet[(block >> 6) & 0x3f]);
        }
        if (remaining > 2)
        {
            result.push_back(kBase64UrlAlphabet[block & 0x3f]);
        }
    }
    return result;
}

std::optional<std::string> base64UrlDecode(std::string_view input)
{
    if (input.size() % 4 == 1)
    {
        return std::nullopt;
    }
    std::array<int, 256> values{};
    values.fill(-1);
    for (int i = 0; i < 64; ++i)
    {
        values[static_cast<unsigned char>(kBase64UrlAlphabet[i])] = i;
    }

    std::string output;
    output.reserve((input.size() * 3) / 4);
    unsigned int buffer = 0;
    int bits = 0;
    for (const unsigned char character : input)
    {
        const int value = values[character];
        if (value < 0)
        {
            return std::nullopt;
        }
        buffer = (buffer << 6) | static_cast<unsigned int>(value);
        bits += 6;
        if (bits >= 8)
        {
            bits -= 8;
            output.push_back(static_cast<char>((buffer >> bits) & 0xff));
        }
    }
    if (bits > 0 && (buffer & ((1U << bits) - 1U)) != 0)
    {
        return std::nullopt;
    }
    return output;
}

std::string hmacSha256(const std::string &value, const std::string &secret)
{
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digestLength = 0;
    if (HMAC(EVP_sha256(),
             secret.data(),
             static_cast<int>(secret.size()),
             reinterpret_cast<const unsigned char *>(value.data()),
             value.size(),
             digest.data(),
             &digestLength) == nullptr)
    {
        throw std::runtime_error("Unable to sign access token");
    }
    return base64UrlEncode(digest.data(), digestLength);
}

std::string lowerAscii(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

std::string trimAscii(const std::string &value)
{
    auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char c) {
        return std::isspace(c) != 0;
    });
    auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char c) {
                    return std::isspace(c) != 0;
                }).base();
    return first < last ? std::string(first, last) : std::string();
}

bool deriveScrypt(const std::string &password,
                  const unsigned char *salt,
                  std::size_t saltLength,
                  unsigned char *key,
                  std::size_t keyLength)
{
    return EVP_PBE_scrypt(password.data(),
                          password.size(),
                          salt,
                          saltLength,
                          kScryptN,
                          kScryptR,
                          kScryptP,
                          kScryptMaxMemory,
                          key,
                          keyLength) == 1;
}
}  // namespace

bool validEmail(const std::string &email)
{
    if (email.empty() || email.size() > 254 ||
        email.find_first_of("\r\n\t ") != std::string::npos)
    {
        return false;
    }
    const auto at = email.find('@');
    if (at == std::string::npos || at == 0 ||
        email.find('@', at + 1) != std::string::npos)
    {
        return false;
    }
    const std::string local = email.substr(0, at);
    const std::string domain = lowerAscii(email.substr(at + 1));
    return local.size() <= 64 && domain == "uharvest.in" &&
           local.front() != '.' && local.back() != '.' &&
           local.find("..") == std::string::npos &&
           std::all_of(local.begin(), local.end(), [](unsigned char c) {
               return std::isalnum(c) != 0 || c == '.' || c == '_' ||
                      c == '+' || c == '-';
           });
}

bool validEmployeeId(const std::string &employeeId)
{
    if (employeeId.empty() || employeeId.size() > 64 ||
        trimAscii(employeeId) != employeeId)
    {
        return false;
    }
    return std::all_of(employeeId.begin(), employeeId.end(), [](unsigned char c) {
        return std::isalnum(c) != 0 || c == '-' || c == '_' || c == '.';
    });
}

bool validPassword(const std::string &password)
{
    if (password.size() < 6 || password.size() > kMaxPasswordBytes ||
        password.find('\0') != std::string::npos)
    {
        return false;
    }
    bool uppercase = false;
    bool number = false;
    bool special = false;
    for (const unsigned char c : password)
    {
        uppercase = uppercase || std::isupper(c) != 0;
        number = number || std::isdigit(c) != 0;
        special = special || (c < 128 && std::isalnum(c) == 0);
    }
    return uppercase && number && special;
}

std::string hashPassword(const std::string &password)
{
    std::array<unsigned char, kScryptSaltBytes> salt{};
    std::array<unsigned char, kScryptKeyBytes> key{};
    if (RAND_bytes(salt.data(), static_cast<int>(salt.size())) != 1 ||
        !deriveScrypt(password, salt.data(), salt.size(), key.data(), key.size()))
    {
        throw std::runtime_error("Unable to hash password");
    }
    return "scrypt$32768$8$1$" + base64UrlEncode(salt.data(), salt.size()) +
           "$" + base64UrlEncode(key.data(), key.size());
}

bool verifyPassword(const std::string &password, const std::string &encodedHash)
{
    constexpr std::string_view prefix = "scrypt$32768$8$1$";
    if (encodedHash.compare(0, prefix.size(), prefix) != 0)
    {
        return false;
    }
    const auto separator = encodedHash.find('$', prefix.size());
    if (separator == std::string::npos)
    {
        return false;
    }
    auto salt = base64UrlDecode(
        std::string_view(encodedHash).substr(prefix.size(),
                                             separator - prefix.size()));
    auto expected =
        base64UrlDecode(std::string_view(encodedHash).substr(separator + 1));
    if (!salt || salt->size() != kScryptSaltBytes || !expected ||
        expected->size() != kScryptKeyBytes)
    {
        return false;
    }
    std::array<unsigned char, kScryptKeyBytes> actual{};
    if (!deriveScrypt(password,
                      reinterpret_cast<const unsigned char *>(salt->data()),
                      salt->size(),
                      actual.data(),
                      actual.size()))
    {
        return false;
    }
    return CRYPTO_memcmp(actual.data(), expected->data(), actual.size()) == 0;
}
 
std::string randomToken(std::size_t byteCount)
{
    if (byteCount == 0 || byteCount > 4096)
    {
        throw std::invalid_argument("Invalid random token size");
    }
    std::vector<unsigned char> bytes(byteCount);
    if (RAND_bytes(bytes.data(), static_cast<int>(bytes.size())) != 1)
    {
        throw std::runtime_error("Unable to create secure random token");
    }
    return base64UrlEncode(bytes.data(), bytes.size());
}

std::string newSessionId()
{
    std::vector<unsigned char> bytes(16);
    if (RAND_bytes(bytes.data(), static_cast<int>(bytes.size())) != 1)
    {
        throw std::runtime_error("Unable to create authentication session");
    }
    static constexpr char hex[] = "0123456789abcdef";
    std::string id;
    id.reserve(bytes.size() * 2);
    for (const unsigned char byte : bytes)
    {
        id.push_back(hex[byte >> 4]);
        id.push_back(hex[byte & 0x0f]);
    }
    return id;
}

std::string sha256Hex(const std::string &value)
{
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digestLength = 0;
    if (EVP_Digest(value.data(),
                   value.size(),
                   digest.data(),
                   &digestLength,
                   EVP_sha256(),
                   nullptr) != 1)
    {
        throw std::runtime_error("Unable to hash token");
    }
    static constexpr char hex[] = "0123456789abcdef";
    std::string result;
    result.reserve(digestLength * 2);
    for (unsigned int i = 0; i < digestLength; ++i)
    {
        result.push_back(hex[digest[i] >> 4]);
        result.push_back(hex[digest[i] & 0x0f]);
    }
    return result;
}

std::string issueAccessToken(std::int64_t userId,
                             const std::string &sessionId,
                             const std::string &secret,
                             std::int64_t issuedAt,
                             std::int64_t expiresAt)
{
    if (secret.size() < 32 || userId <= 0 ||
        expiresAt <= issuedAt ||
        expiresAt - issuedAt > kMaxAccessLifetimeSeconds)
    {
        throw std::invalid_argument("Invalid access token parameters");
    }
    const std::string header = R"({"alg":"HS256","typ":"JWT"})";
    Json::Value payload;
    payload["aud"] = "task-manager-api";
    payload["iss"] = "task-manager-api";
    payload["sub"] = std::to_string(userId);
    payload["sid"] = sessionId;
    payload["iat"] = Json::Int64(issuedAt);
    payload["exp"] = Json::Int64(expiresAt);
    payload["jti"] = randomToken(16);

    Json::StreamWriterBuilder writer;
    writer["indentation"] = "";
    const std::string payloadText = Json::writeString(writer, payload);
    const std::string unsignedToken =
        base64UrlEncode(reinterpret_cast<const unsigned char *>(header.data()),
                        header.size()) +
        "." +
        base64UrlEncode(
            reinterpret_cast<const unsigned char *>(payloadText.data()),
            payloadText.size());
    return unsignedToken + "." + hmacSha256(unsignedToken, secret);
}

std::optional<AccessClaims> verifyAccessToken(const std::string &token,
                                              const std::string &secret,
                                              std::int64_t now)
{
    if (secret.size() < 32 || token.size() > 8192)
    {
        return std::nullopt;
    }
    const auto firstDot = token.find('.');
    const auto secondDot =
        firstDot == std::string::npos ? std::string::npos
                                      : token.find('.', firstDot + 1);
    if (firstDot == std::string::npos || secondDot == std::string::npos ||
        token.find('.', secondDot + 1) != std::string::npos)
    {
        return std::nullopt;
    }
    const auto headerText =
        base64UrlDecode(std::string_view(token).substr(0, firstDot));
    const auto payloadText = base64UrlDecode(std::string_view(token).substr(
        firstDot + 1, secondDot - firstDot - 1));
    const auto signature = base64UrlDecode(
        std::string_view(token).substr(secondDot + 1));
    if (!headerText || !payloadText || !signature)
    {
        return std::nullopt;
    }
    Json::CharReaderBuilder readerBuilder;
    Json::Value header;
    Json::Value payload;
    std::string errors;
    auto reader = std::unique_ptr<Json::CharReader>(readerBuilder.newCharReader());
    if (!reader->parse(headerText->data(),
                       headerText->data() + headerText->size(),
                       &header,
                       &errors) ||
        !reader->parse(payloadText->data(),
                       payloadText->data() + payloadText->size(),
                       &payload,
                       &errors) ||
        !header.isObject() || header["alg"].asString() != "HS256" ||
        header["typ"].asString() != "JWT" ||
        payload["aud"].asString() != "task-manager-api" ||
        payload["iss"].asString() != "task-manager-api" ||
        !payload["sub"].isString() || !payload["sid"].isString() ||
        !payload["exp"].isInt64() || !payload["iat"].isInt64())
    {
        return std::nullopt;
    }
    const std::string unsignedToken = token.substr(0, secondDot);
    const auto expected = base64UrlDecode(hmacSha256(unsignedToken, secret));
    if (!expected || expected->size() != signature->size() ||
        CRYPTO_memcmp(expected->data(), signature->data(), expected->size()) !=
            0)
    {
        return std::nullopt;
    }
    std::int64_t userId = 0;
    try
    {
        std::size_t parsed = 0;
        userId = std::stoll(payload["sub"].asString(), &parsed);
        if (parsed != payload["sub"].asString().size())
        {
            return std::nullopt;
        }
    }
    catch (const std::exception &)
    {
        return std::nullopt;
    }
    const auto issuedAt = payload["iat"].asInt64();
    const auto expiresAt = payload["exp"].asInt64();
    if (userId <= 0 || payload["sid"].asString().empty() ||
        issuedAt > now + 60 || expiresAt <= now || expiresAt <= issuedAt ||
        expiresAt - issuedAt > kMaxAccessLifetimeSeconds)
    {
        return std::nullopt;
    }
    return AccessClaims{userId, payload["sid"].asString(), expiresAt};
}

}  // namespace taskmanager::security
