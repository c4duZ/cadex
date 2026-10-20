//! Why a page did not load, in Portuguese: the reason under "Não foi
//! possível conectar a <endereço>" (docs/spec/preview.md), from WebView2's
//! COREWEBVIEW2_WEB_ERROR_STATUS.

const std = @import("std");
const c = @import("win32").c;

pub fn reason(status: c_int) []const u8 {
    return switch (status) {
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CANNOT_CONNECT, c.COREWEBVIEW2_WEB_ERROR_STATUS_SERVER_UNREACHABLE => "O servidor recusou a conexão ou está fora do ar.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED => "O endereço não foi encontrado.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_TIMEOUT => "O servidor demorou demais para responder.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_DISCONNECTED => "Sem conexão com a internet.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_ABORTED, c.COREWEBVIEW2_WEB_ERROR_STATUS_CONNECTION_RESET => "A conexão caiu.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_COMMON_NAME_IS_INCORRECT,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_EXPIRED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CLIENT_CERTIFICATE_CONTAINS_ERRORS,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_REVOKED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_CERTIFICATE_IS_INVALID,
        => "O certificado do site não é válido.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_ERROR_HTTP_INVALID_SERVER_RESPONSE => "O servidor respondeu algo inválido.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_REDIRECT_FAILED => "O redirecionamento falhou.",
        c.COREWEBVIEW2_WEB_ERROR_STATUS_VALID_AUTHENTICATION_CREDENTIALS_REQUIRED,
        c.COREWEBVIEW2_WEB_ERROR_STATUS_VALID_PROXY_AUTHENTICATION_REQUIRED,
        => "O site pede autenticação.",
        else => "Erro desconhecido.",
    };
}

test "a refused connection reads as such" {
    try std.testing.expectEqualStrings("O endereço não foi encontrado.", reason(c.COREWEBVIEW2_WEB_ERROR_STATUS_HOST_NAME_NOT_RESOLVED));
    try std.testing.expectEqualStrings("Erro desconhecido.", reason(-1));
}

test {
    @import("win32").refAllDeep(@This());
}
