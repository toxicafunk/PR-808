module Component.DrumMachine where

import Audio.Howler (HOWLER)
import Control.Applicative (pure, when)
import Control.Bind (bind, discard)
import Control.Monad.Aff (Aff)
import Control.Monad.Aff.AVar (AVAR)
import Control.Monad.Aff.Class (class MonadAff)
import Control.Monad.Eff.Timer (TIMER, clearInterval, setInterval)
import Data.Array ((..))
import Data.EuclideanRing ((/))
import Data.Foldable (for_)
import Data.Function (const, ($))
import Data.Functor ((<$>))
import Data.HeytingAlgebra (not)
import Data.Lens (Lens, use, (%=), (+=), (.=))
import Data.Lens.Record (prop)
import Data.Maybe (Maybe(..))
import Data.NaturalTransformation (type (~>))
import Data.Ord ((<=))
import Data.Ring ((-))
import Data.Semigroup ((<>))
import Data.Show (show)
import Data.Symbol (SProxy(..))
import Data.Unit (Unit, unit)
import Data.Void (Void, absurd)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.Query.EventSource as ES

import Component.Track as Track

type State = { playing :: Boolean, tracks :: Int, bpm :: Int }

beatSource :: forall f m eff. MonadAff (avar :: AVAR, timer :: TIMER | eff) m => Int -> f ES.SubscribeStatus -> ES.EventSource f m
beatSource tempo = ES.eventSource_' \emit -> do
  intervalId <- H.liftEff $ setInterval (1000 / (tempo / 15)) emit
  pure $ clearInterval intervalId

playing :: forall a b r. Lens { playing :: a | r } { playing :: b | r } a b
playing = prop (SProxy :: SProxy "playing")

tracks :: forall a b r. Lens { tracks :: a | r } { tracks :: b | r } a b
tracks = prop (SProxy :: SProxy "tracks")

bpm :: forall a b r. Lens { bpm :: a | r } { bpm :: b | r } a b
bpm = prop (SProxy :: SProxy "bpm")

data Query a = PlayStop a
             | PlayLoop (ES.SubscribeStatus -> a)
             | AddTrack a
             | RemoveTrack a
             | IncreaseBPM a
             | DecreaseBPM a

type Input = Unit
type Message = Void

type Slot = Int

drumMachine :: forall eff. H.Component HH.HTML Query Input Message (Aff (howler :: HOWLER, avar :: AVAR, timer :: TIMER | eff))
drumMachine =
  H.parentComponent
    { initialState: const initialState
    , render
    , eval
    , receiver: const Nothing
    }
  where

  initialState :: State
  initialState = { playing: false, tracks: 1, bpm: 120 }

  render :: State -> H.ParentHTML Query Track.Query Slot (Aff (howler :: HOWLER, avar :: AVAR, timer :: TIMER | eff))
  render state =
    HH.div_
      [ HH.h1_
          [ HH.text "PR-808" ]
      , HH.button
          [ HE.onClick (HE.input_ DecreaseBPM) ]
          [ HH.text "DOWN TEMPO" ]
      , HH.span_
          [ HH.text $ show state.bpm <> " BPM"]
      , HH.button
          [ HE.onClick (HE.input_ IncreaseBPM) ]
          [ HH.text "UP TEMPO" ]
      , HH.button
          [ HE.onClick (HE.input_ PlayStop) ]
          [ HH.text
              if state.playing
                then "Stop"
                else "Play"
          ]
      , HH.button
          [ HE.onClick (HE.input_ AddTrack) ]
          [ HH.text "+" ]
      , HH.button
          [ HE.onClick (HE.input_ RemoveTrack) ]
          [ HH.text "-" ]
      , HH.div_ (renderTrack <$> 1..state.tracks)
      ]

  renderTrack :: Slot -> H.ParentHTML Query Track.Query Slot (Aff (howler :: HOWLER, avar :: AVAR, timer :: TIMER | eff))
  renderTrack n = HH.div_ [ HH.slot n Track.track unit absurd ]

  eval :: Query ~> H.ParentDSL State Query Track.Query Slot Message (Aff (howler :: HOWLER, avar :: AVAR, timer :: TIMER | eff))
  eval = case _ of
    PlayStop next -> do
      playing' <- use playing
      when (not playing') do
        bpm' <- use bpm
        H.subscribe (beatSource bpm' $ H.request PlayLoop)
      playing %= not
      pure next
    PlayLoop reply -> do
      playing' <- use playing
      tracks' <- use tracks
      if playing'
        then do
          for_ (1..tracks') \trackNumber ->
            H.query trackNumber $ H.action Track.NextBeat
          pure $ reply ES.Listening
        else do
          for_ (1..tracks') \trackNumber ->
            H.query trackNumber $ H.action Track.ResetCurrentStep
          pure $ reply ES.Done
    AddTrack next -> do
     tracks += 1
     pure next
    RemoveTrack next -> do
     tracks %= \n -> if n <= 1 then 1 else n - 1
     pure next
    IncreaseBPM next -> do
     bpm += 5
     playing .= false
     pure next
    DecreaseBPM next -> do
     bpm %= \n -> if n <= 5 then 5 else n - 5
     playing .= false
     pure next