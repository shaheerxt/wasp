{-# LANGUAGE TypeApplications #-}

module Wasp.AppSpec.Valid
  ( validateAppSpec,
    ValidationError (..),
    getApp,
    isAuthEnabled,
  )
where

import Control.Monad (unless)
import Data.List (find)
import Data.Maybe (isJust)
import Text.Read (readMaybe)
import Text.Regex.TDFA ((=~))
import Wasp.AppSpec (AppSpec)
import qualified Wasp.AppSpec as AS
import Wasp.AppSpec.App (App)
import qualified Wasp.AppSpec.App as AS.App
import qualified Wasp.AppSpec.App as App
import qualified Wasp.AppSpec.App.Auth as Auth
import qualified Wasp.AppSpec.App.Db as AS.Db
import qualified Wasp.AppSpec.App.Wasp as Wasp
import Wasp.AppSpec.Core.Decl (takeDecls)
import qualified Wasp.AppSpec.Entity as Entity
import qualified Wasp.AppSpec.Entity.Field as Entity.Field
import qualified Wasp.AppSpec.Page as Page
import Wasp.AppSpec.Util (isPgBossJobExecutorUsed)
import qualified Wasp.SemanticVersion as SV
import qualified Wasp.Version as WV

data ValidationError = GenericValidationError String
  deriving (Eq)

instance Show ValidationError where
  show (GenericValidationError e) = e

validateAppSpec :: AppSpec -> [ValidationError]
validateAppSpec spec =
  case validateExactlyOneAppExists spec of
    Just err -> [err]
    Nothing ->
      -- NOTE: We check these only if App exists because they all rely on it existing.
      concat
        [ validateWasp spec,
          validateAppAuthIsSetIfAnyPageRequiresAuth spec,
          validateAuthUserEntityHasCorrectFieldsIfUsernameAndPasswordAuthIsUsed spec,
          validateExternalAuthEntityHasCorrectFieldsIfExternalAuthIsUsed spec,
          validateDbIsPostgresIfPgBossUsed spec
        ]

validateExactlyOneAppExists :: AppSpec -> Maybe ValidationError
validateExactlyOneAppExists spec =
  case AS.takeDecls @App (AS.decls spec) of
    [] -> Just $ GenericValidationError "You are missing an 'app' declaration in your Wasp app."
    [_] -> Nothing
    apps ->
      Just $
        GenericValidationError $
          "You have more than one 'app' declaration in your Wasp app. You have " ++ show (length apps) ++ "."

validateWasp :: AppSpec -> [ValidationError]
validateWasp = validateWaspVersion . Wasp.version . App.wasp . snd . getApp

validateWaspVersion :: String -> [ValidationError]
validateWaspVersion specWaspVersionStr = eitherUnitToErrorList $ do
  specWaspVersionRange <- parseWaspVersionRange specWaspVersionStr
  unless (SV.isVersionInRange WV.waspVersion specWaspVersionRange) $
    Left $ incompatibleVersionError WV.waspVersion specWaspVersionRange
  where
    -- TODO: Use version range parser from SemanticVersion when it is fully implemented.

    parseWaspVersionRange :: String -> Either ValidationError SV.Range
    parseWaspVersionRange waspVersionRangeStr = do
      -- Only ^x.y.z is allowed here because it was the easiest solution to start
      -- with at the moment. In the future, we plan to allow any SemVer
      -- definition.
      let (_ :: String, _ :: String, _ :: String, waspVersionRangeDigits :: [String]) =
            waspVersionRangeStr =~ ("\\`\\^([0-9]+)\\.([0-9]+)\\.([0-9]+)\\'" :: String)

      waspSpecVersion <- case mapM readMaybe waspVersionRangeDigits of
        Just [major, minor, patch] -> Right $ SV.Version major minor patch
        __ -> Left $ GenericValidationError "Wasp version should be in the format ^major.minor.patch"

      Right $ SV.Range [SV.backwardsCompatibleWith waspSpecVersion]

    incompatibleVersionError :: SV.Version -> SV.Range -> ValidationError
    incompatibleVersionError actualVersion expectedVersionRange =
      GenericValidationError $
        unlines
          [ "Your Wasp version does not match the app's requirements.",
            "You are running Wasp " ++ show actualVersion ++ ".",
            "This app requires Wasp " ++ show expectedVersionRange ++ ".",
            "To install specific version of Wasp, do:",
            "  curl -sSL https://get.wasp-lang.dev/installer.sh | sh -s -- -v x.y.z",
            "where x.y.z is your desired version.",
            "Check https://github.com/wasp-lang/wasp/releases for the list of valid versions."
          ]

    eitherUnitToErrorList :: Either e () -> [e]
    eitherUnitToErrorList (Left e) = [e]
    eitherUnitToErrorList (Right ()) = []

validateAppAuthIsSetIfAnyPageRequiresAuth :: AppSpec -> [ValidationError]
validateAppAuthIsSetIfAnyPageRequiresAuth spec =
  [ GenericValidationError
      "Expected app.auth to be defined since there are Pages with authRequired set to true."
    | anyPageRequiresAuth && not (isAuthEnabled spec)
  ]
  where
    anyPageRequiresAuth = any ((== Just True) . Page.authRequired) (snd <$> AS.getPages spec)

validateDbIsPostgresIfPgBossUsed :: AppSpec -> [ValidationError]
validateDbIsPostgresIfPgBossUsed spec =
  [ GenericValidationError
      "Expected app.db.system to be PostgreSQL since there are jobs with executor set to PgBoss."
    | isPgBossJobExecutorUsed spec && not (isPostgresUsed spec)
  ]

validateAuthUserEntityHasCorrectFieldsIfUsernameAndPasswordAuthIsUsed :: AppSpec -> [ValidationError]
validateAuthUserEntityHasCorrectFieldsIfUsernameAndPasswordAuthIsUsed spec = case App.auth (snd $ getApp spec) of
  Nothing -> []
  Just auth ->
    if not $ Auth.isUsernameAndPasswordAuthEnabled auth
      then []
      else
        let userEntity = snd $ AS.resolveRef spec (Auth.userEntity auth)
            userEntityFields = Entity.getFields userEntity
         in concatMap
              (validateEntityHasField "app.auth.userEntity" userEntityFields)
              [ ("username", Entity.Field.FieldTypeScalar Entity.Field.String, "String"),
                ("password", Entity.Field.FieldTypeScalar Entity.Field.String, "String")
              ]

validateExternalAuthEntityHasCorrectFieldsIfExternalAuthIsUsed :: AppSpec -> [ValidationError]
validateExternalAuthEntityHasCorrectFieldsIfExternalAuthIsUsed spec = case App.auth (snd $ getApp spec) of
  Nothing -> []
  Just auth ->
    if not $ Auth.isExternalAuthEnabled auth
      then []
      else case Auth.externalAuthEntity auth of
        Nothing -> [GenericValidationError "app.auth.externalAuthEntity must be specified when using a social login method."]
        Just externalAuthEntityRef ->
          let (userEntityName, userEntity) = AS.resolveRef spec (Auth.userEntity auth)
              userEntityFields = Entity.getFields userEntity
              (externalAuthEntityName, externalAuthEntity) = AS.resolveRef spec externalAuthEntityRef
              externalAuthEntityFields = Entity.getFields externalAuthEntity
              externalAuthEntityValidationErrors =
                concatMap
                  (validateEntityHasField "app.auth.externalAuthEntity" externalAuthEntityFields)
                  [ ("provider", Entity.Field.FieldTypeScalar Entity.Field.String, "String"),
                    ("providerId", Entity.Field.FieldTypeScalar Entity.Field.String, "String"),
                    ("user", Entity.Field.FieldTypeScalar (Entity.Field.UserType userEntityName), userEntityName),
                    ("userId", Entity.Field.FieldTypeScalar Entity.Field.Int, "Int")
                  ]
              userEntityValidationErrors =
                concatMap
                  (validateEntityHasField "app.auth.userEntity" userEntityFields)
                  [ ("externalAuthAssociations", Entity.Field.FieldTypeComposite $ Entity.Field.List $ Entity.Field.UserType externalAuthEntityName, externalAuthEntityName ++ "[]")
                  ]
           in externalAuthEntityValidationErrors ++ userEntityValidationErrors

validateEntityHasField :: String -> [Entity.Field.Field] -> (String, Entity.Field.FieldType, String) -> [ValidationError]
validateEntityHasField entityName entityFields (fieldName, fieldType, fieldTypeName) =
  let maybeField = find ((== fieldName) . Entity.Field.fieldName) entityFields
   in case maybeField of
        Just providerField
          | Entity.Field.fieldType providerField == fieldType -> []
        _ ->
          [ GenericValidationError $
              "Expected an Entity referenced by " ++ entityName ++ " to have field '" ++ fieldName ++ "' of type '" ++ fieldTypeName ++ "'."
          ]

-- | This function assumes that @AppSpec@ it operates on was validated beforehand (with @validateAppSpec@ function).
-- TODO: It would be great if we could ensure this at type level, but we decided that was too much work for now.
--   Check https://github.com/wasp-lang/wasp/pull/455 for considerations on this and analysis of different approaches.
getApp :: AppSpec -> (String, App)
getApp spec = case takeDecls @App (AS.decls spec) of
  [app] -> app
  apps ->
    error $
      ("Expected exactly 1 'app' declaration in your wasp code, but you have " ++ show (length apps) ++ ".")
        ++ " This should never happen as it should have been caught during validation of AppSpec."

-- | This function assumes that @AppSpec@ it operates on was validated beforehand (with @validateAppSpec@ function).
isAuthEnabled :: AppSpec -> Bool
isAuthEnabled spec = isJust (App.auth $ snd $ getApp spec)

-- | This function assumes that @AppSpec@ it operates on was validated beforehand (with @validateAppSpec@ function).
isPostgresUsed :: AppSpec -> Bool
isPostgresUsed spec = Just AS.Db.PostgreSQL == (AS.Db.system =<< AS.App.db (snd $ getApp spec))
