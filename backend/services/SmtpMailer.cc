#include "SmtpMailer.h"

#include <curl/curl.h>

#include <algorithm>
#include <charconv>
#include <cstdlib>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>

namespace taskmanager
{
namespace
{
using CurlHandle = std::unique_ptr<CURL, decltype(&curl_easy_cleanup)>;
using RecipientList =
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)>;

struct MessageReader
{
    const std::string &message;
    std::size_t offset = 0;
};

std::string requiredEnvironment(const char *name)
{
    const char *value = std::getenv(name);
    if (!value || value[0] == '\0')
    {
        throw std::runtime_error(std::string(name) + " must be configured");
    }
    return value;
}

bool safeHeaderValue(const std::string &value)
{
    return value.find_first_of("\r\n\t<> ") == std::string::npos &&
           value.find('@') != std::string::npos;
}

void checkCurl(CURLcode result, const std::string &context)
{
    if (result != CURLE_OK)
    {
        throw std::runtime_error(context + ": " + curl_easy_strerror(result));
    }
}

template <typename Value>
void setOption(CURL *curl, CURLoption option, Value value)
{
    checkCurl(curl_easy_setopt(curl, option, value),
              "Unable to configure SMTP request");
}

size_t readMessage(char *buffer,
                   size_t size,
                   size_t count,
                   void *userData)
{
    if (size != 0 && count > std::numeric_limits<size_t>::max() / size)
    {
        return CURL_READFUNC_ABORT;
    }

    auto &reader = *static_cast<MessageReader *>(userData);
    const size_t capacity = size * count;
    const size_t remaining = reader.message.size() - reader.offset;
    const size_t bytesToRead = std::min(capacity, remaining);
    std::copy_n(reader.message.data() + reader.offset, bytesToRead, buffer);
    reader.offset += bytesToRead;
    return bytesToRead;
}

std::string smtpUrl(const std::string &host, std::uint16_t port)
{
    std::string url = "smtps://";
    if (host.find(':') != std::string::npos)
    {
        url += "[" + host + "]";
    }
    else
    {
        url += host;
    }
    return url + ":" + std::to_string(port) + "/";
}
}  // namespace

SmtpMailer::SmtpMailer(std::string host,
                       std::uint16_t port,
                       std::string username,
                       std::string password,
                       std::string fromAddress)
    : host_(std::move(host)),
      port_(port),
      username_(std::move(username)),
      password_(std::move(password)),
      fromAddress_(std::move(fromAddress))
{
    if (host_.empty() || host_.find_first_of("\r\n\t /?#@") !=
                             std::string::npos ||
        port_ == 0 || !safeHeaderValue(fromAddress_))
    {
        throw std::invalid_argument("Invalid SMTP configuration");
    }
}

SmtpMailer SmtpMailer::fromEnvironment()
{
    const auto portText = [] {
        const char *value = std::getenv("TASK_MANAGER_SMTP_PORT");
        return value && value[0] != '\0' ? std::string(value) : "465";
    }();
    unsigned int port = 0;
    const auto result = std::from_chars(
        portText.data(), portText.data() + portText.size(), port);
    if (result.ec != std::errc() ||
        result.ptr != portText.data() + portText.size() || port == 0 ||
        port > 65535)
    {
        throw std::runtime_error(
            "TASK_MANAGER_SMTP_PORT must be 1 to 65535");
    }
    return SmtpMailer(requiredEnvironment("TASK_MANAGER_SMTP_HOST"),
                      static_cast<std::uint16_t>(port),
                      requiredEnvironment("TASK_MANAGER_SMTP_USER"),
                      requiredEnvironment("TASK_MANAGER_SMTP_PASSWORD"),
                      requiredEnvironment("TASK_MANAGER_EMAIL_FROM"));
}

void SmtpMailer::sendVerificationCode(const std::string &email,
                                     const std::string &token)
{
    if (!safeHeaderValue(email))
    {
        throw std::invalid_argument("Invalid verification recipient address");
    }

    static const CURLcode globalInitResult =
        curl_global_init(CURL_GLOBAL_DEFAULT);
    checkCurl(globalInitResult, "Unable to initialize libcurl");

    CurlHandle curl(curl_easy_init(), curl_easy_cleanup);
    if (!curl)
    {
        throw std::runtime_error("Unable to create SMTP request");
    }

    curl_slist *rawRecipients = curl_slist_append(nullptr, email.c_str());
    if (!rawRecipients)
    {
        throw std::runtime_error("Unable to configure SMTP recipient");
    }
    RecipientList recipients(rawRecipients, curl_slist_free_all);

    const std::string message =
        "From: " + fromAddress_ + "\r\n" +
        "To: " + email + "\r\n" +
        "Subject: Verify your Task Manager account\r\n" +
        "MIME-Version: 1.0\r\n" +
        "Content-Type: text/plain; charset=UTF-8\r\n\r\n" +
        "Your Task Manager email verification code is:\r\n\r\n" + token +
        "\r\n\r\nThis code expires in 24 hours. If you did not request this, "
        "you can ignore this message.\r\n";
    MessageReader reader{message};

    const std::string url = smtpUrl(host_, port_);
    setOption(curl.get(), CURLOPT_URL, url.c_str());
    setOption(curl.get(), CURLOPT_USERNAME, username_.c_str());
    setOption(curl.get(), CURLOPT_PASSWORD, password_.c_str());
    setOption(curl.get(), CURLOPT_MAIL_FROM, fromAddress_.c_str());
    setOption(curl.get(), CURLOPT_MAIL_RCPT, recipients.get());
    setOption(curl.get(), CURLOPT_UPLOAD, 1L);
    setOption(curl.get(), CURLOPT_READFUNCTION, readMessage);
    setOption(curl.get(), CURLOPT_READDATA, &reader);
    setOption(curl.get(),
              CURLOPT_INFILESIZE_LARGE,
              static_cast<curl_off_t>(message.size()));
    setOption(curl.get(), CURLOPT_CONNECTTIMEOUT, 10L);
    setOption(curl.get(), CURLOPT_TIMEOUT, 30L);
    setOption(curl.get(), CURLOPT_NOSIGNAL, 1L);
    setOption(curl.get(), CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);
    setOption(curl.get(), CURLOPT_SSL_VERIFYPEER, 1L);
    setOption(curl.get(), CURLOPT_SSL_VERIFYHOST, 2L);

    checkCurl(curl_easy_perform(curl.get()),
              "Unable to send verification email");
}

}  // namespace taskmanager
