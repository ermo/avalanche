/*
 * SPDX-FileCopyrightText: Copyright © 2020-2022 Serpent OS Developers
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * avalanche.app
 *
 * Main application runtime for build control
 *
 * Authors: Copyright © 2020-2022 Serpent OS Developers
 * License: Zlib
 */

module avalanche.rest;

import vibe.d;
import avalanche.build;
import avalanche.build.job;
import avalanche.rest.pairing;
import avalanche.rest.stats;
import moss.service.tokens.manager;
import moss.db.keyvalue;

/**
 * Used in the statistics API
 */
public struct TimeDatapoint
{
    /**
     * When the samople was taken
     */
    long timestamp;

    /**
     * Sample value
     */
    double value;
}

/**
 * Simple format memory report
 */
public struct MemoryReport
{
    /**
     * How much memory exists?
     */
    double total;

    /* Free memory */
    TimeDatapoint[] free;

    /* Available memory */
    TimeDatapoint[] available;

    /* Used memory */
    TimeDatapoint[] used;
}

/**
 * Simplistic API that powers our charts
 */
@path("/api/v1/stats") public interface StatsAPIv1
{
    /**
     * Current memory usage
     */
    @path("memory") @method(HTTPMethod.GET) MemoryReport memory() @safe;
}

/**
 * The BuildAPI
 */
@path("/api/v1") public interface BuildAPIv1
{
    @path("version")
    string versionIdentifier() @safe;

    /**
     * Request a build.
     */
    @path("build_package")
    void buildPackage(PackageBuild request) @safe;
}

/**
 * Main entry point from the server side, storing our
 * databases and interfaces.
 */
public final class BuildAPI : BuildAPIv1
{

    @disable this();

    /**
     * Construct new BuildAPI using the specified rootDir
     */
    this(string rootDir) @safe
    {
        this.rootDir = rootDir;
    }

    /**
     * Configure BuildAPI for integration
     */
    @noRoute void configure(Database appDB, TokenManager tokenManager, URLRouter root) @safe
    {
        auto apiRoot = root.registerRestInterface(this);
        auto pair = new AvalanchePairingAPI();
        pair.configure(appDB, tokenManager, apiRoot);
        auto stats = new AvalancheStats();
        stats.configure(root);
    }

    override string versionIdentifier() @safe
    {
        return "0.0.1";
    }

    /**
     * Go ahead and schedule build of the package on a separate fiber
     */
    override void buildPackage(PackageBuild request) @safe
    {
        enforceHTTP(!working, HTTPStatus.serviceUnavailable, "Sorry, already building something");
        enforceHTTP(request.collections.length > 0, HTTPStatus.badRequest, "Missing collections");
        working = true;
        runTask({ auto b = new BuildJob(rootDir, request); b.run(); working = false; });
    }

private:

    string rootDir;
    bool working = false;
}
