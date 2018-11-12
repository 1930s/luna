-----------------------------------------------------------------------------
-- When using this module please keep in mind that it will not, by default,
-- catch any exceptions thrown in IO. To catch exceptions thrown in IO, please
-- use `rethrowFromIO` in `Control.Monad.Exception.IO` to lift these exceptions
-- into the MonadException framework.
--
-- If you are getting an overlapping instances error in conjunction with use of
-- `rethrowFromIO`, you are probably attempting to rethrow `SomeException`. This
-- is considered bad practice, so please rethrow something more specific.
-----------------------------------------------------------------------------

{-# LANGUAGE NoStrict #-}
{-# LANGUAGE NoStrictData #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeInType #-}

module Control.Monad.Exception where

import Data.Kind
import Prelude

import qualified Control.Exception as IO

import Control.Exception          (Exception, SomeException, toException)
import Control.Monad              (join)
import Control.Monad.Trans        (MonadTrans, lift)
import Control.Monad.Trans.Except (ExceptT, runExceptT, throwE)
import GHC.Exts                   (Constraint)

-------------------------------
-- === Exception raising === --
-------------------------------

-- === MonadException === --

type SomeExceptT = ExceptT SomeException

class Monad m => MonadException e m where
    throw :: ∀ a. e -> m a

type family MonadExceptions es m :: Constraint where
    MonadExceptions '[]       m = ()
    MonadExceptions (e ': es) m = (MonadException e m, MonadExceptions es m)


-- === Utils === --

catch :: ∀ e m a. Monad m => (e -> m a) -> ExceptT e m a -> m a
catch f = join . fmap (either f return) . runExceptT ; {-# INLINE catch #-}

catchAll :: ∀ m a. Monad m => (SomeException -> m a) -> SomeExceptT m a -> m a
catchAll = catch ; {-# INLINE catchAll #-}

tryAll :: ∀ m a. SomeExceptT m a -> m (Either SomeException a)
tryAll = runExceptT ; {-# INLINE tryAll #-}


-- === Throws === --

type family   Throws (e :: k)     (m :: * -> *) :: Constraint
type instance Throws (e :: [Type]) m = MonadExceptions e m
type instance Throws (e :: Type)   m = MonadException  e m


-- === Instances === --

instance {-# OVERLAPPABLE #-}
    (Monad m, Monad (t m), MonadTrans t, MonadException e m)
    => MonadException e (t m) where
    throw = lift . throw ; {-# INLINE throw #-}

instance {-# OVERLAPPABLE #-} (Monad m, Exception e)
    => MonadException e (ExceptT e m) where
    throw = throwE ; {-# INLINE throw #-}

instance (Monad m, Exception e)
    => MonadException e (ExceptT SomeException m) where
    throw = throwE . toException ; {-# INLINE throw #-}

instance Exception e => MonadException e IO where
    throw = IO.throw ; {-# INLINE throw #-}



-------------------
-- === Utils === --
-------------------

fromJust :: Throws e m => e -> Maybe a -> m a
fromJust e = \case
    Nothing -> throw e
    Just a  -> return a
{-# INLINE fromJust #-}
