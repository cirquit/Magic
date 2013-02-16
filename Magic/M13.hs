{-# LANGUAGE OverloadedStrings #-}

module Magic.M13 where

import Magic.Types
import Magic.ObjectTypes
import Magic.Target
import Magic.Utils
import Magic.Core
import Magic.Events
import Magic.Labels

import Control.Applicative
import Control.Monad (void)
import Data.Label.Pure (get)
import Data.Label.PureM ((=:), asks)
import qualified Data.Set as Set


instantSpeed :: ObjectRef -> PlayerRef -> View Bool
instantSpeed rSelf rActivator =
  case rSelf of
    (Hand rp, _) -> return (rp == rActivator)
    _            -> return False

sorcerySpeed :: ObjectRef -> PlayerRef -> View Bool
sorcerySpeed rSelf rp = (&&) <$> instantSpeed rSelf rp <*> myMainPhase
  where
    myMainPhase = do
      ap <- asks activePlayer
      as <- asks activeStep
      return (ap == rp && as == MainPhase)

-- | The effect of playing a permanent without targets that uses the stack.
playPermanentEffect :: ObjectRef -> PlayerRef -> Magic ()
playPermanentEffect rSelf _ = void $
    view (willMoveToStack rSelf (pure resolvePermanent)) >>= executeEffect
  where
    resolvePermanent _source = return ()

stackingPlayAbility :: ManaPool -> [AdditionalCost] -> Ability
stackingPlayAbility mc ac rSelf rActivator =
  ClosedAbility
    { _available       = do
      self <- asks (object rSelf)
      if hasTypes instantType self || Flash `elem` get staticKeywordAbilities self
        then instantSpeed rSelf rActivator
        else sorcerySpeed rSelf rActivator
    , _manaCost        = mc
    , _additionalCosts = ac
    , _effect          = playPermanentEffect rSelf rActivator
    , _isManaAbility   = False
    }

stackTargetlessEffect :: ObjectRef -> (Object -> Magic ()) -> Magic ()
stackTargetlessEffect rSelf item = do
  eff <- view (willMoveToStack rSelf (pure item))
  void $ executeEffect eff

ajani'sSunstriker :: Card
ajani'sSunstriker = mkCard $ do
  name      =: Just "Ajani's Sunstriker"
  types     =: creatureType
  pt        =: Just (2, 2)
  play     =: (Just $ \rSelf rActivator ->
    ClosedAbility
      { _available       = sorcerySpeed rSelf rActivator
      , _manaCost        = [Just White, Just White]
      , _additionalCosts = []
      , _effect          = playPermanentEffect rSelf rActivator
      , _isManaAbility   = False
      })
  staticKeywordAbilities =: [Lifelink]

angel'sMercy :: Card
angel'sMercy = mkCard $ do
  name =: Just "Angel's Mercy"
  types =: instantType
  play =: (Just $ \rSelf rActivator ->
    ClosedAbility
      { _available = instantSpeed rSelf rActivator
      , _manaCost = [Nothing, Nothing, Just White, Just White]
      , _additionalCosts = []
      , _effect = stackTargetlessEffect rSelf $ \_ ->
                    void $ executeEffect (Will (AdjustLife rActivator 7))
      , _isManaAbility = False
      }
    )

attendedKnight :: Card
attendedKnight = mkCard $ do
    name      =: Just "Attended Knight"
    types     =: objectTypes [Human, Knight]
    pt        =: Just (2, 2)
    play      =: (Just $ \rSelf rActivator ->
      ClosedAbility
        { _available       = sorcerySpeed rSelf rActivator
        , _manaCost        = [Nothing, Nothing, Just White]
        , _additionalCosts = []
        , _effect          = playPermanentEffect rSelf rActivator
        , _isManaAbility   = False
        })
    staticKeywordAbilities =: [FirstStrike]
    triggeredAbilities     =: [trigger]
  where
    trigger :: TriggeredAbility
    trigger rSelf@(Battlefield, iSelf) (DidMoveObject _ (Battlefield, iOther))
      | iSelf == iOther  = Just . void . mkTriggerObject <$> asks (object rSelf .^ controller)
    trigger _ _          = return Nothing

    mkTriggerObject :: PlayerRef -> Magic ()
    mkTriggerObject p = void $ executeEffect $ WillCreateObject Stack $
      (emptyObject undefined p) { _stackItem = Just (triggerStackItem p) }

    triggerStackItem :: PlayerRef -> StackItem
    triggerStackItem p = pure $ \_self ->
      void $ executeEffect $ WillCreateObject Battlefield $ (emptyObject undefined p)
        { _name      = Just "Soldier"
        , _colors    = Set.singleton White
        , _types     = objectType Soldier
        , _tapStatus = Just Untapped
        , _pt        = Just (2, 2)
        }

searingSpear :: Card
searingSpear = mkCard $ do
  name  =: Just "Searing Spear"
  types =: instantType
  play  =: (Just $ \rSelf rActivator ->
    ClosedAbility
      { _available = instantSpeed rSelf rActivator
      , _manaCost = [Nothing, Just Red]
      , _additionalCosts = []
      , _effect = searingSpearEffect rSelf rActivator
      , _isManaAbility = False
      })

searingSpearEffect :: ObjectRef -> PlayerRef -> Magic ()
searingSpearEffect rSelf rActivator = do
  let ok t = case t of
              TargetObject r@(Battlefield, _) -> hasTypes creatureType <$> asks (object r)
              TargetPlayer _                  -> return True
              _                               -> return False
  ts <- askMagicTargets rActivator (singleTarget <?> ok)
  let f :: Target -> Object -> Magic ()
      f t source = void $ executeEffect $ case t of
        TargetObject r -> Will (DamageObject source r 3 False True)
        TargetPlayer r -> Will (DamagePlayer source r 3 False True)
  void (view (willMoveToStack rSelf (f <$> ts)) >>= executeEffect)
