{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
module Data.Macaw.PPC.PPCReg (
  PPCReg(..),
  linuxSystemCallPreservedRegisters,
  ArchWidth(..)
  ) where

import           GHC.TypeLits

import           Data.Proxy ( Proxy(..) )
import qualified Data.Set as S
import qualified Data.Macaw.CFG as MC
import qualified Data.Macaw.Memory as MM
import           Data.Macaw.Types
import           Data.Parameterized.Classes
import           Data.Parameterized.Some ( Some(..) )
import qualified Data.Parameterized.TH.GADT as TH

import qualified Dismantle.PPC as D
import qualified SemMC.Architecture.PPC32 as PPC32
import qualified SemMC.Architecture.PPC64 as PPC64

data PPCReg arch tp where
  PPC_GP :: (w ~ MC.RegAddrWidth (PPCReg arch), 1 <= w) => D.GPR -> PPCReg arch (BVType w)
  PPC_IP :: (w ~ MC.RegAddrWidth (PPCReg arch), 1 <= w) => PPCReg arch (BVType w)
  PPC_LNK :: (w ~ MC.RegAddrWidth (PPCReg arch), 1 <= w) => PPCReg arch (BVType w)
  PPC_CTR :: (w ~ MC.RegAddrWidth (PPCReg arch), 1 <= w) => PPCReg arch (BVType w)
  PPC_CR :: PPCReg arch (BVType 32)

deriving instance Eq (PPCReg arch tp)
deriving instance Ord (PPCReg arch tp)

instance Show (PPCReg arch tp) where
  show r =
    case r of
      PPC_GP gpr -> show gpr
      PPC_IP -> "ip"
      PPC_LNK -> "lnk"
      PPC_CTR -> "ctr"
      PPC_CR -> "cr"

instance ShowF (PPCReg arch) where
  showF = show

$(return [])

instance TestEquality (PPCReg arch) where
  testEquality = $(TH.structuralTypeEquality [t| PPCReg |] [])

instance OrdF (PPCReg arch) where
  compareF = $(TH.structuralTypeOrd [t| PPCReg |] [])

-- | The set of registers preserved across Linux system calls is defined by the ABI.
--
-- Currently, we are only considering the non-volatile GPRs.  There are also a
-- set of non-volatile floating point registers.  I have to check on the vector
-- registers.
--
-- NOTE: As the name implies, this is Linux-specific.  Other ABIs will require
-- an analysis here.  That said, these are the register specs suggested by the
-- architecture manual, so they should be pretty consistent across ABIs.
linuxSystemCallPreservedRegisters :: (w ~ MC.RegAddrWidth (PPCReg ppc), 1 <= w)
                                  => proxy ppc
                                  -> S.Set (Some (PPCReg ppc))
linuxSystemCallPreservedRegisters _ =
  S.fromList [ Some (PPC_GP (D.GPR rnum)) | rnum <- [14..31] ]

type instance MC.RegAddrWidth (PPCReg PPC32.PPC) = 32
type instance MC.RegAddrWidth (PPCReg PPC64.PPC) = 64

type instance MC.ArchReg PPC64.PPC = PPCReg PPC64.PPC
type instance MC.ArchReg PPC32.PPC = PPCReg PPC32.PPC

class ArchWidth arch where
  pointerNatRepr :: proxy arch -> NatRepr (MC.RegAddrWidth (PPCReg arch))

instance ArchWidth PPC32.PPC where
  pointerNatRepr _ = n32

instance ArchWidth PPC64.PPC where
  pointerNatRepr _ = n64

instance (ArchWidth ppc) => HasRepr (PPCReg ppc) TypeRepr where
  typeRepr r =
    case r of
      PPC_GP {} -> BVTypeRepr (pointerNatRepr (Proxy @ppc))
      PPC_IP -> BVTypeRepr (pointerNatRepr (Proxy @ppc))
      PPC_LNK -> BVTypeRepr (pointerNatRepr (Proxy @ppc))
      PPC_CTR -> BVTypeRepr (pointerNatRepr (Proxy @ppc))
      PPC_CR -> BVTypeRepr n32

instance (MM.MemWidth w, ArchWidth ppc, w ~ MC.RegAddrWidth (PPCReg ppc), 1 <= w)
       => MC.RegisterInfo (PPCReg ppc) where
  archRegs = ppcRegs
  sp_reg = PPC_GP (D.GPR 1)
  ip_reg = PPC_IP
  syscall_num_reg = PPC_GP (D.GPR 0)
  syscallArgumentRegs = [ PPC_GP (D.GPR rnum) | rnum <- [3..10] ]

ppcRegs :: forall w ppc
         . (w ~ MC.RegAddrWidth (PPCReg ppc), 1 <= w)
        => [Some (PPCReg ppc)]
ppcRegs = concat [ gprs
                 ]
  where
    gprs = [ Some (PPC_GP (D.GPR rnum))
           | rnum <- [0..31]
           ]
