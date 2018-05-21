-- {-# LANGUAGE Strict               #-}
{-# LANGUAGE UndecidableInstances #-}

module Data.Graph.Traversal.Scoped where

import Prologue hiding (Traversable, fold, fold1, traverse)

import qualified Control.Monad.State.Layered     as State
import qualified Data.Generics.Traversable       as GTraversable
import qualified Data.Graph.Data.Component.Class as Component
import qualified Data.Graph.Data.Component.Set   as Setx
import qualified Data.Graph.Data.Graph.Class     as Graph
import qualified Data.Graph.Data.Layer.Class     as Layer
import qualified Data.Graph.Data.Layer.Layout    as Layout
import qualified Data.Graph.Traversal.Fold       as Fold
import qualified Data.Map.Strict                 as Map
import qualified Data.Set                        as Set
import qualified Foreign.Ptr                     as Ptr
import qualified Foreign.Storable                as Storable
import qualified Type.Data.List                  as List

import Data.Generics.Traversable       (GTraversable)
import Data.Graph.Data.Component.Class (Component)
import Data.PtrList.Mutable            (UnmanagedPtrList)
import Data.Set                        (Set)
import Data.Vector.Storable.Foreign    (Vector)
import Foreign.Ptr.Utils               (SomePtr)
import Type.Data.Bool                  (Not, type (||))



--------------------
-- === Scoped === --
--------------------

-- === Scope === --

data Scope
    = All
    | Whitelist [Type]
    | Blacklist [Type]

type family LayerScope t :: Scope

type        EnabledLayer   t layer = EnabledLayer__ (LayerScope t) layer
type family EnabledLayer__ t layer where
    EnabledLayer__ 'All             _ = 'True
    EnabledLayer__ ('Whitelist lst) l =      List.In l lst
    EnabledLayer__ ('Blacklist lst) l = Not (List.In l lst)


-- === Definition === --

data Scoped t
type instance Fold.Result(Scoped t) = Fold.Result t
type instance LayerScope (Scoped t) = LayerScope  t

class Monad m => LayerBuilder t m layer where
    layerBuild :: ∀ layout. Layer.Cons layer layout -> m (Fold.Result t) -> m (Fold.Result t)

class Monad m => ComponentBuilder t m comp where
    componentBuild :: ∀ layout. Component comp layout -> m (Fold.Result t) -> m (Fold.Result t)


-- === Defaults === --

instance {-# OVERLAPPABLE #-} (Monad m, Fold.Builder1 t m (Layer.Cons layer))
      => LayerBuilder t m layer where
    layerBuild = Fold.build1 @t
    {-# INLINE layerBuild #-}

instance {-# OVERLAPPABLE #-} Monad m => ComponentBuilder t m comp where
    componentBuild = \_ -> id
    {-# INLINE componentBuild #-}


-- === Instances === --

instance {-# OVERLAPPABLE #-}
         ( layers ~ Graph.DiscoverComponentLayers m tag
         , ComponentBuilder t m tag
         , LayersFoldableBuilder__ t layers m )
      => Fold.Builder (Scoped t) m (Component tag layout) where
    build = Fold.build1 @(Scoped t)
    {-# INLINE build #-}

instance {-# OVERLAPPABLE #-}
         ( layers ~ Graph.DiscoverComponentLayers m tag
         , ComponentBuilder t m tag
         , LayersFoldableBuilder__ t layers m )
      => Fold.Builder1 (Scoped t) m (Component tag) where
    build1 = \comp mr -> componentBuild @t comp
        $! buildLayersFold__ @t @layers (Component.unsafeToPtr comp) mr
    {-# INLINE build1 #-}



----------------------
-- === Internal === --
----------------------

-- === FoldableLayers === --

class Monad m => LayersFoldableBuilder__ t (layers :: [Type]) m where
    buildLayersFold__ :: SomePtr -> m (Fold.Result t) -> m (Fold.Result t)

instance Monad m => LayersFoldableBuilder__ t '[] m where
    buildLayersFold__ = \_ a -> a
    {-# INLINE buildLayersFold__ #-}

instance ( MonadIO m
         , Storable.Storable (Layer.Cons l ())
         , Layer.StorableLayer l m
         , LayerFoldableBuilder__ (EnabledLayer t l) t m l
         , LayersFoldableBuilder__ t ls m )
     => LayersFoldableBuilder__ t (l ': ls) m where
    buildLayersFold__ = \ptr mr -> do
        let fs   = buildLayersFold__ @t @ls ptr'
            ptr' = Ptr.plusPtr ptr $ Layer.byteSize @l
        layerBuild__ @(EnabledLayer t l) @t @m @l ptr $! fs mr
    {-# INLINE buildLayersFold__ #-}


-- === LayerBuilder === --

class Monad m => LayerFoldableBuilder__ (active :: Bool) t m layer where
    layerBuild__ :: SomePtr -> m (Fold.Result t) -> m (Fold.Result t)

instance {-# OVERLAPPABLE #-} Monad m
      => LayerFoldableBuilder__ 'False t m layer where
    layerBuild__ = \_ a -> a
    {-# INLINE layerBuild__ #-}

instance (Monad m, Layer.StorableLayer layer m, LayerBuilder t m layer)
      => LayerFoldableBuilder__ 'True t m layer where
    layerBuild__ = \ptr mr -> do
        layer <- Layer.unsafePeekWrapped @layer ptr
        r     <- mr -- | Performance
        layerBuild @t @m @layer layer (pure r)
    {-# INLINE layerBuild__ #-}