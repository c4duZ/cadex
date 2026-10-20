//! Why a page did not load, in the interface's language (ADR 0015): the
//! reason under "Could not connect to <address>" (docs/spec/preview.md),
//! from WebView2's COREWEBVIEW2_WEB_ERROR_STATUS.

const std = @import("std");
const c = @import("win32").c;
const t = @import("strings").t;

pub fn reason(status: c_int) []const u8 {
    return switch (status) {
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT, c.COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE => t("The server refused the connection or is down.", "O servidor recusou a conexão ou está fora do ar."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED => t("The address was not found.", "O endereço não foi encontrado."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT => t("The server took too long to answer.", "O servidor demorou demais para responder."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED => t("No internet connection.", "Sem conexão com a internet."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED, c.COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET => t("The connection dropped.", "A conexão caiu."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID,
        => t("The site's certificate is not valid.", "O certificado do site não é válido."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_ERROR_HTTP_INVALID_SERVER_RESPONSE => t("The server sent an invalid response.", "O servidor respondeu algo inválido."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_REDIRECT_FAILED => t("The redirect failed.", "O redirecionamento falhou."),
        c.COREWEBVIEW2_WEB_ERROR_STATUS_VALID_AUTHENTICATION_CREDENTIALS_REQUIRED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_VALID_PROXY_AUTHENTICATION_REQUIRED,
        => t("The site asks for authentication.", "O site pede autenticação."),
        else => t("Unknown error.", "Erro desconhecido."),
    };
}

test "a refused connection reads as such" {
    try std.testing.expectEqualStrings("The address was not found.", reason(c.COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED));
    try std.testing.expectEqualStrings("Unknown error.", reason(-1));
}

test {
    @import("win32").refAllDeep(@This());
}
