------------------------------- MODULE skeen -------------------------------

(* 
  Skeen's protocol [1] is encoded in TLA+.   
   
  [1] Skeen, D.: (1985), Referenced in [1], unpublished communication.

  [2] Birman, K.P., Joseph, T.A.: Reliable communication in the presence of failures.
      ACM Transactions on Computer Systems (TOCS) 5(1), 47–76 (1987)
  
   Thanh-Hai Tran, Igor Konnov, Josef Widder, 2021
   This file is a subject to the license that is bundled together with this package 
   and can be found in the file LICENSE. 
 *)


EXTENDS Integers,  FiniteSets, Sequences, TLC


(* Type operator for APALACHE *)
a <: b == a

(* All variables *)
VARIABLE clock, phase, localTS, globalTS, rcvdMcastID, mcastedID,   
            inTransit, delivered, proposeTS, dCntr
  
vars == << clock, phase, localTS, globalTS, rcvdMcastID, mcastedID, 
            inTransit, delivered, proposeTS, dCntr >>

CONSTANT N,           \* the number of processes indexed from 1 to N
         M,           \* the number of multicast messages indexed from 1 to M
         GroupDest,   \* an array whose i-th element describes the group of addressees of message i 
         Mcaster,     \* an array whose i-th element describes the multicaster of message i
         MaxClock     \* the bound of local clocks


Proc == 1..N
McastID == 1..M
MType == 10         \* type of multicast messages
PType == 11         \* type of proposed messages
Start == 12
Proposed == 13 
Committed == 14

ASSUME
  /\ N \in Int
  /\ \A id \in McastID : GroupDest[id] \in SUBSET Int 
  /\ MType \in Int
  /\ PType \in Int
  /\ Start \in Int
  /\ Proposed \in Int
  /\ Committed \in Int
  /\ M = Cardinality(McastID)

McastMsgPhase == {Start, Proposed, Committed}
                       
McastPhase == [McastID -> McastMsgPhase]                              


\* TimestampNull: the init value of local timestamps and global timestamps
\* Type of TimestampNull is [t |-> Int, g |-> Int] 
GroupNull == 0 
TimeNull == 0
TimestampNull == [t |-> TimeNull, g |-> GroupNull] <: [t |-> Int, g |-> Int]  

Time == 1..MaxClock    
ProcWithNull == 0..N            
            
\* The set of all possible in-transit messages            
TimestampSet == [t : Time, g : Proc] \cup {TimestampNull} \* <: {[t |-> Int, g |-> Int]} ) \cup ({TimestampNull}  <: {[g : Int, t : Int]})     
McastMsgSet   == [t : Time, id : McastID, type : {MType}, source : Proc] <: {[type |-> Int, t |-> Int, id |-> Int, source |-> Int]}  
ProposeMsgSet == [t : Time, id : McastID, type : {PType}, source : Proc] <: {[type |-> Int, t |-> Int, id |-> Int, source |-> Int]}
InTransitMsgSet == McastMsgSet \cup ProposeMsgSet

          
(* 
  The initialized states
    - clock: local clocks
    - phase[p][m]: stores the status of message m at process p
    - localTS[p][m]: stores the local timestamp issued by process p for message m
    - globalTS[p][m]: stores the global timestamp issued by process p for message m
    - delivered[p][m]: refers to whether process p has delivered message m
    - rcvdMcastID[p][m]: a set of multicast messages that process p has received
    - proposeTS[p][m]: stores a set of proposals for messages m  
    - mcastedID: a set of messages that were multicast
    - inTransit[p][q]: a set of in-transit messages from process p to process q
    - dCntr[p][m] to keep trach of how many times process p has delivered message m.
 *) 
Init ==  
  /\ clock = [p \in Proc |-> 0]
  /\ phase = [p \in Proc |-> [m \in McastID |-> Start]]
  /\ localTS = [p \in Proc |-> [m \in McastID |-> TimestampNull]]
  /\ globalTS = [p \in Proc |-> [m \in McastID |-> TimestampNull]]
  /\ delivered = [p \in Proc |-> [m \in McastID |-> FALSE]]
  /\ rcvdMcastID = [p \in Proc |-> ({} <: {Int} ) ] 
  /\ proposeTS = [p \in Proc |-> [id \in McastID |-> ({} <: {[type |-> Int, t |-> Int, id |-> Int, source |-> Int]}) ] ]  
  /\ mcastedID = ({} <: {Int})
  /\ inTransit = [p \in Proc |-> [q \in Proc |-> ({} <: {[type |-> Int, t |-> Int, id |-> Int, source |-> Int]})]]
  /\ dCntr = [p \in Proc |-> [id \in McastID |-> 0]]
                                      

Max(a, b) == IF a > b THEN a ELSE b


\* Process snder multicasts the message whose identifier is mid.       
\* The multicast message for message mid is tag with a local timestamp issued by process snder.
Multicast(mid) ==    
  LET snder == Mcaster[mid]
  IN  /\ mid \notin mcastedID   
      /\ clock[snder] < MaxClock              \* Only for bounded model checking 
      /\ snder \in GroupDest[mid]             
      /\ mcastedID' = mcastedID \cup {mid}    \* Marks that message mid is multicast
      /\ LET time == clock[snder] + 1
             msg ==  ([ type |-> MType, id |-> mid, t |-> time, source |-> snder ] <: [type |-> Int, t |-> Int, source |-> Int, id |-> Int])
         IN   /\ inTransit' = [p \in Proc |-> [q \in Proc |-> 
                                  IF p = snder /\ q \in GroupDest[mid]
                                  THEN inTransit[p][q] \cup {msg}
                                  ELSE inTransit[p][q]]]
              /\ clock' = [ clock EXCEPT ![snder] = time ]
              /\ UNCHANGED << phase, proposeTS, rcvdMcastID, localTS, globalTS, delivered, dCntr >>
              
      
\* Pick the in-transit message with the smallest timestamp from process snder to process rcver   
isYoungestMsg(snder, rcver, msg) ==
  \A m \in inTransit[snder][rcver] : msg.t <= m.t   
   
   
\* Receives a multicast message   
ReceiveMulticast(snder, rcver, msg) ==   
  /\ clock[rcver] < MaxClock
  /\ msg.type = MType      
  /\ isYoungestMsg(snder, rcver, msg)     \* msg must have the smallest timestamp in inTransit[snder][rcver]
  /\ rcvdMcastID' = [rcvdMcastID EXCEPT ![rcver] = rcvdMcastID[rcver] \cup {msg.id}] 
  /\ UNCHANGED << proposeTS, globalTS, delivered, mcastedID, dCntr >>
  /\ LET mid == msg.id
         time == clock[rcver] + 1
         newTS == [ t |-> time, g |-> rcver ]       \* the local timestamp for message msg.id                             
         newMsg == ([ type |-> PType, id |-> mid, source |-> rcver, t |-> time ] <: [type |-> Int, t |-> Int, source |-> Int, id |-> Int])    \* the proposal for message msg.id                       
     IN /\ clock' = [clock EXCEPT ![rcver] = clock[rcver] + 1]        
        /\ localTS' = [localTS EXCEPT ![rcver][mid] = newTS]          
        /\ phase' = [phase EXCEPT ![rcver][mid] = Proposed]
        \* Sends its proposal to every addressee of message msg.id
        /\ IF snder # rcver                 
           THEN inTransit' = [p \in Proc |-> [q \in Proc |-> 
                                  IF p = rcver /\ q \in GroupDest[mid]
                                  THEN inTransit[p][q] \cup {newMsg}                                      
                                  ELSE IF p = snder /\ q = rcver
                                       THEN inTransit[p][q] \ {msg}
                                       ELSE inTransit[p][q] ]] 
            ELSE inTransit' = [p \in Proc |-> [q \in Proc |-> 
                                  IF p = rcver /\ q = rcver
                                  THEN (inTransit[p][q] \cup {newMsg}) \ {msg}
                                  ELSE IF p = rcver /\ q \in GroupDest[mid]
                                       THEN inTransit[p][q] \cup {newMsg}                                      
                                       ELSE inTransit[p][q] ]]
        
   
\* Compare two timestamps based on lexicographical order
Less(ts1, ts2) ==
  \/ ts1.t < ts2.t
  \/ /\ ts1.t = ts2.t
     /\ ts1.g < ts2.g   



\* Check whether message id can be delivered to process p                                
CanDeliver(p, id) ==
  /\ ~delivered[p][id] 
  /\ phase'[p][id] = Committed
  /\ \A mid \in rcvdMcastID'[p] : \* The local timestamps of all committed messages must be greater than the global timestamp of message id  
        phase'[p][mid] = Proposed => Less(globalTS'[p][id], localTS'[p][mid]) 
                                                                       
\* Process rcver has received the proposals from all addressees of message id. 
HasAllProposes(rcver, id) ==
  \A p \in GroupDest[id] : \E m \in proposeTS'[rcver][id] : m.source = p
 
\* Pick a proposed message with the greatest local timestamp for message id
PickMsgWithMaxTS(rcver, id) == 
  CHOOSE m \in proposeTS'[rcver][id] : 
    \A m1 \in proposeTS'[rcver][id] : 
        \/ m1.t < m.t
        \/ /\ m1.t = m.t 
           /\ m1.source <= m.source

\* Process rcver has received a proposed message from process snder 
ReceivePropose(snder, rcver, msg) ==   
  /\ msg.type = PType
  /\ isYoungestMsg(snder, rcver, msg)     \* msg must have the smallest timestamp in inTransit[snder][rcver]
  /\ inTransit' = [inTransit EXCEPT ![snder][rcver] = inTransit[snder][rcver] \ {msg}]  
  /\ LET ts == [ t |-> msg.t, g |-> msg.source]
         id == msg.id
     IN /\ UNCHANGED << localTS, mcastedID, rcvdMcastID  >>
        /\ proposeTS' = [proposeTS EXCEPT ![rcver][id] = proposeTS[rcver][id] \cup {msg} ]              
        /\ IF HasAllProposes(rcver, id)                                                   \* Check whether process rcver has received the proposals from all addressees of message id.            
           THEN LET m == PickMsgWithMaxTS(rcver, id)                                      \* Pick a proposed message with the greatest local timestamp for message id           
                    maxTS == [ g |-> m.source, t |-> m.t ]                             
                IN /\ globalTS' = [globalTS EXCEPT ![rcver][id] = maxTS]                  \* Set the global timestamp for message msg.id
                   /\ clock' = [clock EXCEPT ![rcver]  = Max(clock[rcver], maxTS.t)]      \* Synchronizes the local clocks             
                   /\ phase' = [phase EXCEPT ![rcver][id] = Committed]                
                   /\ delivered' = [ delivered EXCEPT ![rcver] = [mid \in McastID |-> 
                                        IF ~delivered[rcver][mid]
                                        THEN CanDeliver(rcver, mid)
                                        ELSE delivered[rcver][mid] ]]  
                   /\ dCntr' = [ dCntr EXCEPT ![rcver] = [ mid \in McastID |->            \* Update the number of times that process p has delivered message mid
                                        IF ~delivered[rcver][mid] /\ CanDeliver(rcver, mid)
                                        THEN dCntr[rcver][mid] + 1
                                        ELSE dCntr[rcver][mid] ] ]                                                                
           ELSE UNCHANGED <<phase, globalTS, clock, delivered, dCntr>>
           
           
\* Only to avoid deadlock checking 
Done ==
  /\ \A id \in McastID : \A p \in GroupDest[id] : delivered[p][id]
  /\ UNCHANGED vars 
     
Next == 
  \/ \E m \in McastID : Multicast(m) 
  \/ \E snder, rcver \in Proc : \E msg \in inTransit[snder][rcver] : ReceiveMulticast(snder, rcver, msg)  
  \/ \E snder, rcver \in Proc : \E msg \in inTransit[snder][rcver] : ReceivePropose(snder, rcver, msg)
  \/ Done


Spec == 
  /\ Init 
  /\ [][Next]_vars
  /\ WF_vars( \/ \E m \in McastID : Multicast(m) 
              \/ \E snder, rcver \in Proc : \E msg \in inTransit[snder][rcver] : ReceiveMulticast(snder, rcver, msg)  
              \/ \E snder, rcver \in Proc : \E msg \in inTransit[snder][rcver] : ReceivePropose(snder, rcver, msg) )    


    
=============================================================================
\* Modification History
\* Last modified Thu Mar 25 22:10:07 CET 2021 by tran
\* Created Tue Mar 16 08:59:43 CET 2021 by tran