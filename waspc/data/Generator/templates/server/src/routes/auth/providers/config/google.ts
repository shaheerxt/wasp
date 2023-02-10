import { setupOAuthRouter } from "../oauth/setupRouter.js";
import { makeOAuthInit } from "../oauth/init.js";

import { ProviderConfig, ProviderType } from "../types.js";

const config: ProviderConfig = {
    name: ProviderType.google,
    slug: "google",
    init: makeOAuthInit({
        npmPackage: 'passport-google-oauth20',
        passportImportPath: '../../passport/google/config.js',
    }),
    setupRouter: setupOAuthRouter,
}

export default config;
