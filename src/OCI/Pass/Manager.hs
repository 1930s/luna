module OCI.Pass.Manager where

import Prologue

import Control.Monad.Exception     (Throws, throw)
import Control.Monad.State.Layered (MonadState, StateT)
import Data.Map.Strict             (Map)
import Data.Set                    (Set)

import qualified Control.Monad.State.Layered as State
import qualified Data.Map.Strict             as Map
import qualified Data.Set                    as Set

import Control.Lens (at)

---------------------------
-- === ComponentInfo === --
---------------------------

-- === Definition === --

data ComponentInfo = ComponentInfo
    { _layers :: Map SomeTypeRep LayerInfo
    } deriving (Show)

data LayerInfo = LayerInfo deriving (Show)

instance Default ComponentInfo where
    def = ComponentInfo def ; {-# INLINE def #-}

instance Default LayerInfo where
    def = LayerInfo ; {-# INLINE def #-}


makeLenses ''ComponentInfo
-- instance Default LayerInfo where
--     def = LayerInfo ; {-# INLINE def #-}
--
--


--------------------
-- === Errors === --
--------------------


data PassManagerError
    = DuplicateComponent SomeTypeRep
    | DuplicateLayer     SomeTypeRep SomeTypeRep
    | MissingComponent   SomeTypeRep
    deriving (Show)


instance Exception PassManagerError

-------------------------
-- === PassManager === --
-------------------------

-- === Definition === --

data State = State
    { _components :: Map SomeTypeRep ComponentInfo
    -- , _primLayers :: Map SomeTypeRep LayerInfo
    } deriving (Show)
makeLenses ''State

type MonadPassManager m = (MonadState State m, Throws PassManagerError m)

newtype PassManagerT m a = PassManagerT (StateT State m a)
    deriving ( Applicative, Alternative, Functor, Monad, MonadFail, MonadFix
             , MonadIO, MonadPlus, MonadTrans, MonadThrow)
makeLenses ''PassManagerT


-- === Running === --

evalT :: Functor m => PassManagerT m a -> m a
evalT = State.evalDefT . unwrap ; {-# INLINE evalT #-}




-- === Component management === --

registerComponentRep :: MonadPassManager m => SomeTypeRep -> m ()
registerComponentRep comp = State.modifyM_ @State $ \m -> do
    when_ (Map.member comp $ m ^. components) . throw $ DuplicateComponent comp
    return $ m & components %~ Map.insert comp def
{-# INLINE registerComponentRep #-}

registerPrimLayerRep :: MonadPassManager m => SomeTypeRep -> SomeTypeRep -> m ()
registerPrimLayerRep comp layer = State.modifyM_ @State $ \m -> do
    components' <- flip (at comp) (m ^. components) $ \case
        Nothing       -> throw $ MissingComponent comp
        Just compInfo -> do
            when_ (Map.member layer $ compInfo ^. layers) $
                throw $ DuplicateLayer comp layer
            return $ Just $ compInfo & layers %~ Map.insert layer def
    return $ m & components .~ components'
{-# INLINE registerPrimLayerRep #-}

registerComponent :: ∀ comp m.       (MonadPassManager m, Typeable comp) => m ()
registerPrimLayer :: ∀ comp layer m. (MonadPassManager m, Typeable comp, Typeable layer) => m ()
registerComponent = registerComponentRep (someTypeRep @comp) ; {-# INLINE registerComponent #-}
registerPrimLayer = registerPrimLayerRep (someTypeRep @comp) (someTypeRep @layer) ; {-# INLINE registerPrimLayer #-}


-- === Instances === --

instance Monad m => State.MonadGetter State (PassManagerT m) where
    get = wrap State.get' ; {-# INLINE get #-}

instance Monad m => State.MonadSetter State (PassManagerT m) where
    put = wrap . State.put' ; {-# INLINE put #-}

instance Default State where
    def = State def ; {-# INLINE def #-}


test :: PassManagerT IO ()
test = do
    x <- State.get @State
    return ()