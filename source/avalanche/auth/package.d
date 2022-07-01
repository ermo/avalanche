/*
 * SPDX-FileCopyrightText: Copyright © 2020-2022 Serpent OS Developers
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * avalanche.auth
 *
 * Authentication + authorization helpers for REST
 *
 * Authors: Copyright © 2020-2022 Serpent OS Developers
 * License: Zlib
 */

module avalanche.auth;

import jwt = jwtd.jwt;
import std.datetime : SysTime, UTC, Clock;
import std.exception : assumeUnique;
import std.json : JSONValue;
import std.stdint : uint8_t, uint64_t;
import std.string : startsWith, strip;
import std.sumtype;
import vibe.d : HTTPStatusException, HTTPStatus, logError;

/**
 * A token key is just a sequence of bytes.
 */
public alias TokenString = ubyte[];

/**
 * Authentication can fail for numerous reasons
 */
public enum TokenErrorType : uint8_t
{
    /**
     * No error detected
     */
    None = 0,

    /**
     * Incorrect token format
     */
    InvalidFormat,

    /**
     * Invalid JSON
     */
    InvalidJSON,
}

/**
 * Simplistic wrapping of errors
 */
public struct TokenError
{
    TokenErrorType type;
    string errorString;

    auto toString() @safe @nogc nothrow const
    {
        return errorString;
    }
}

/**
 * Tokens must include sub/iss/iat/eat
 */
public struct Token
{
    /**
     * Primary subject (i.e. user) of the Token
     */
    string subject;

    /**
     * Who issued it?
     */
    string issuer;

    /**
     * Date and time when the Token was issued (UTC)
     */
    SysTime issuedAt;

    /**
     * Date and time when the Token expires (UTC)
     */
    SysTime expiresAt;

    /**
     * True if this token has expired by UTC time
     */
    @property bool expiredUTC() @safe nothrow
    {
        auto tnow = Clock.currTime(UTC());
        return tnow > expiresAt;
    }
}

/**
 * Our methods can either return a token or an error.
 */
public alias TokenReturn = SumType!(Token, TokenError);

/**
 * A TokenAuthenticator is a thin shim around the JWT library.
 * Currently we use HMAC and require all of our services to run
 * over SSL.
 */
public class TokenAuthenticator
{

    /**
     * Initialise the authenticator with our own key
     */
    this(TokenString ourKey) @system
    {
        this.ourKey = assumeUnique(ourKey);
    }

    invariant ()
    {
        assert(ourKey !is null);
    }

    /**
     * Attempt to decode the input, or fail spectacularly
     */
    TokenReturn decode(TokenString input)
    {
        JSONValue value;
        Token tok;
        try
        {
            value = jwt.decode(cast(string) input, cast(string) ourKey);
        }
        catch (jwt.VerifyException ex)
        {
            return TokenReturn(TokenError(TokenErrorType.InvalidFormat, cast(string) ex.message));
        }

        /* Decode the JSON now */
        try
        {
            tok.issuer = value["iss"].get!string;
            tok.subject = value["sub"].get!string;
            auto iat = value["iat"].get!uint64_t;
            auto eat = value["exp"].get!uint64_t;
            tok.issuedAt = SysTime.fromUnixTime(iat, UTC());
            tok.expiresAt = SysTime.fromUnixTime(eat, UTC());
        }
        catch (Exception ex)
        {
            return TokenReturn(TokenError(TokenErrorType.InvalidJSON, cast(string) ex.message));
        }
        return TokenReturn(tok);
    }

    /**
     * Check our header and potentially throw an error until its correct looking
     */
    Token checkTokenHeader(string authHeader)
    {
        if (!authHeader.startsWith("Bearer"))
        {
            throw new HTTPStatusException(HTTPStatus.badRequest);
        }
        /* Strip the header down */
        auto substr = authHeader["B earer".length .. $].strip();
        logError(substr);
        Token ret;

        /* Get it decoded. */
        this.decode(cast(TokenString) substr).match!((TokenError err) {
            logError("Invalid token encountered: %s", err.toString);
            throw new HTTPStatusException(HTTPStatus.expectationFailed, err.toString);
        }, (Token t) { ret = t; });

        /* Check expiry, subject, etc. */
        return ret;
    }

private:

    immutable(TokenString) ourKey;
}