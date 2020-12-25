/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  用于医嘱处理的公共服务类
/// -100 医嘱不存在
/// -209 状态不符合
/// -205 更新医嘱状态失败
/// -206 更新停止信息失败
/// -207 护士已经扫过条码,请撤销后再处理医嘱
/// -202 更新预停信息失败
/// -203 已经执行的医嘱不能停止
/// -201 已经停止的医嘱不用再停
/// -202 已经计费的医嘱不允许作废
Class appcom.OEOrdItem Extends %RegisteredObject [ ClassType = "", ProcedureBlock ]
{

/// Creator:      周志强
/// CreatDate:    2012.03.27
/// Description:  医生撤销执行医嘱,用于医技科室取消执行
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).Verifye("77078||14",127) 
ClassMethod Verify(OrdItmRowId As %String, UserRowId As %String) As %String
{
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"					//医嘱不存在

	set OEORIItemStatDR=obj.OEORIItemStatDR
	set OEORIItemStateCode=$s($IsObject(OEORIItemStatDR):OEORIItemStatDR.OSTATCode,1:"")
	d obj.%Close()
	s obj=""
	if (OEORIItemStateCode'="E") Quit "-209"   		//执行状态的医嘱才能变为核实

	s StatusRowId=$O(^OEC("OSTAT",0,"Code","V",0))
	TS
	s err=..UpdateStatus(OrdItmRowId,UserRowId,StatusRowId)
	if err Tro  Q "-205"                            //更新医嘱状态及变化表
	
	//检验医嘱撤销清空字段
	&SQL(Update SQLUser.OE_ORDITEM 
			Set OEORI_LabTestSetRow="",OEORI_LabEpisodeSetup=NULL,
				OEORI_LabReceiveDate=NULL, OEORI_LabReceiveTime=NULL
    where OEORI_RowId=:OrdItmRowId)
	if SQLCODE Tro  Q "-205" 
	
	s err=##class(appcom.OEOrdExec).VerifyAll(OrdItmRowId,UserRowId)
	if err Tro  Q err   
			
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId)
		if err {
			s err="-205"
			Quit
		}
		//检验医嘱撤销清空字段
		&SQL(Update SQLUser.OE_ORDITEM  
				Set OEORI_LabTestSetRow="",OEORI_LabEpisodeSetup=NULL,
					OEORI_LabReceiveDate=NULL, OEORI_LabReceiveTime=NULL
	    where OEORI_RowId=:SubRowId)
	    
		if SQLCODE Quit
		s err=##class(appcom.OEOrdExec).VerifyAll(SubRowId,UserRowId)
		if err Quit
		
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	TC
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.27
/// Description:  医生执行医嘱
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).Execute("110||68",108) 
ClassMethod Execute(OrdItmRowId As %String, UserRowId As %String) As %String
{
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"					//医嘱不存在

	set OEORIItemStatDR=obj.OEORIItemStatDR
	set OEORIItemStateCode=$s($IsObject(OEORIItemStatDR):OEORIItemStatDR.OSTATCode,1:"")
	d obj.%Close()
	s obj=""
	if (OEORIItemStateCode'="V") Quit "-209"   		//非核实状态的医嘱不能执行

	s StatusRowId=$O(^OEC("OSTAT",0,"Code","E",0))
	TS
	s err=..UpdateStatus(OrdItmRowId,UserRowId,StatusRowId)
	if err Tro  Q "-205"                            //更新医嘱状态及变化表
	;标版放开控制
	;屏蔽,如果检验,检查执行记录也变为执行,没有流程业务可以撤销.对于计费已经判断了医嘱的执行状态
	s err=##class(appcom.OEOrdExec).ExecuteAll(OrdItmRowId,UserRowId)
	if err Tro  Q err   
			
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId)
		if err {
			s err="-205"
			Quit
		}
		
		;s err=##class(appcom.OEOrdExec).ExecuteAll(SubRowId,UserRowId)
		;if err Quit
		
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	TC
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  撤销单条医嘱,长期医嘱或临时医嘱开立后因为某种原因不再有效而失效,
///               但需要在医嘱单上记录。实际上该状态可以用"停止"状态代替，
///               是否需要这个状态要按医院的实际需求决定
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).Cancel("52||17",600) 
ClassMethod Cancel(OrdItmRowId As %String, UserRowId As %String, ReasonDr As %String = "", ReasonDesc As %String = "", IsBillN As %String = "Y") As %String
{
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"					//医嘱不存在
	
	;1 调用计费接口 是拆账单的产生的自定价医嘱不可以停
	s ArcimRowId=$p($G(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1)),"^",2)
	s Rtn=##class(web.UDHCJFIntBill).JudgeArcIsorNot(ArcimRowId)
	if (Rtn=1){
		Q "-15304"
	}
	s OEORIChildsub=$o(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,""))
	if (OEORIChildsub'=""){
		 s mOrdItm=""
	}else{
		s mOrdItm=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),11)),"^",39)
	}
	//判断主医嘱跟关联医嘱是否在同一账单(只考虑未结算账单)
	s Rtn=##class(web.DHCBillInterface).ICheckBillIsSplit(OrdItmRowId,mOrdItm)
	if (Rtn="Y"){
		Q "-15307"
	}
	//实库库管进行了医嘱提取，需要经过高值材料库管员退货确认
	if ("Y"'=##class(web.DHCSTM.PCHCOLLSM).GetRetFlag(OrdItmRowId)) {
		q "-210"
	}
	s StopAllExecItemCat=$g(^DHCDocConfig("StopAllExecItemCat"))
	s itemrowid=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),1)),"^",2)
    s ItemCatRowId=+$p($g(^ARCIM(+$g(itemrowid),1,1)),"^",10)
    s StopAllExecFlag=0
	i ("^"_StopAllExecItemCat_"^")[("^"_ItemCatRowId_"^") s StopAllExecFlag=1 
	if (StopAllExecFlag'="1"){
		if ..Executed(OrdItmRowId) Q "-302"
	}
	if ##class(DHCDoc.DHCDocCure.Record).FindCureRecordByOEORI(OrdItmRowId)=1  Q "-15306"
	;set OEORIUserAdd=obj.OEORIUserAddGetObjectId()
	;if OEORIUserAdd'=UserRowId set err="-208" quit err     	//撤销医嘱要和下医嘱人一致
	
	set OEORIItemStatDR=obj.OEORIItemStatDR
	set OEORIItemStateCode=$s($IsObject(OEORIItemStatDR):OEORIItemStatDR.OSTATCode,1:"")
	set OEORIPlacerNo=obj.OEORIPlacerNo
	set OEORIBilled=obj.OEORIBilled
	set PAADMType=obj.OEORIOEORDParRef.OEORDAdmDR.PAADMType
	set ARCItemCat=obj.OEORIItmMastDR.ARCIMItemCatDR.%Id()
	d obj.%Close()	s obj=""

	if (PAADMType="O")||(PAADMType="E") {
		s CFOPStopPaidItemCat=##Class(web.DHCDocConfig).GetConfigNode("OPStopPaidItemCat")
		if CFOPStopPaidItemCat'="" s CFOPStopPaidItemCat="^"_CFOPStopPaidItemCat_"^"
		Q:(CFOPStopPaidItemCat'[("^"_ARCItemCat_"^"))&(OEORIBilled="P") "-202"
	}else{
		Q:(OEORIBilled="P") "-202"	;已计费不能作废医嘱
	}
	if (OEORIItemStateCode'="V") Quit "-2091" //撤销的能作废，作废的不能撤销
	//if (OEORIItemStateCode'="V")&&(OEORIItemStateCode'="U") Quit "-209"   //非核实状态的医嘱不能作废
	if OEORIPlacerNo'="" Quit "-207"

	s StatusRowId=$O(^OEC("OSTAT",0,"Code","C",0))
	
	s ret=..UpdateExtIfPractice(OrdItmRowId,UserRowId,StatusRowId)
	Q:ret'=0 ret
	TS
	s err=..UpdateStatus(OrdItmRowId,UserRowId,StatusRowId,ReasonDr,ReasonDesc)
	if err Tro  Q "-205"                            //更新医嘱状态及变化表
	;临时医嘱作废或者撤销可以直接停止执行记录,撤销和作废自动停止所有执行记录
	s StopFlag=1
	/*
	s PriorRowId= $p($g(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1)),"^",8)
	if ##class(appcom.OEOrdItem).ISShortOrderPrior(PriorRowId) {
		s StopFlag=1
	}
	*/
	//调用医技接口位置放在医嘱状态改变之后，执行记录改变之前
    ;调用服务总线接口
	s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(OrdItmRowId,UserRowId,"2")
	;非药理子类的检验检查药理项目需要撤销免费
	s PPRowID=$p($G(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),"DHC")),"^",10)
	if (PPRowID'=""){
		s err=##class(web.PilotProject.DHCDocPilotProject).CancelPPAOrdFree(PPRowID,OrdItmRowId,UserRowId)
		if err  Tro  Q err
	}
	s err=##Class(appcom.OEOrdExec).DiscontinueAll(OrdItmRowId,UserRowId,StopFlag,IsBillN,StopAllExecFlag)    //停止所有执行记录
	if err  Tro  Q err
	
	;如果没有停医嘱人(护士办理出院结算自动停医嘱),则取下医嘱人
	if UserRowId="" s UserRowId=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),7)),"^",1)
	&SQL(Select SSUSR_CareProv_DR into :DoctorRowId from SQLUser.SS_User where SSUSR_RowId=:UserRowId )
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	
	s CFOPStopPaidItemCat=##Class(web.DHCDocConfig).GetConfigNode("OPStopPaidItemCat")
	if CFOPStopPaidItemCat'="" s CFOPStopPaidItemCat="^"_CFOPStopPaidItemCat_"^"
	
	if PAADMType="I" {
		if $g(DoctorRowId)="" {  
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:OrdItmRowId)
		}else{
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:OrdItmRowId)
		}
	}else{
		if $g(DoctorRowId)="" {  
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_Billed='I' where OEORI_rowid=:OrdItmRowId)
		}else{
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId,OEORI_Billed='I' where OEORI_rowid=:OrdItmRowId)
		}
	}
	if SQLCODE TRo  Q "-206"
	
	//撤销医嘱外部接口
	s err=..CancelOrdDocInterface(OrdItmRowId,UserRowId)
	if +err'=0  Tro  Q err
	
	/*;调用服务总线接口
	s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(OrdItmRowId,UserRowId)*/
			
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		s SubStatusCode=..GetStatusCode(SubRowId)
		if (SubStatusCode="D")||(SubStatusCode="U")||(SubStatusCode="C") {
			s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
			continue
		}
				
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId,ReasonDr,ReasonDesc)
		if err {
			s err="-205"
			Quit
		}
		
	
		if PAADMType="I" {
			if DoctorRowId="" { 
				&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:SubRowId)
			}else{
				&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:SubRowId)
			}
		}else{
			if DoctorRowId="" { 
				&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_Billed='I' where OEORI_rowid=:SubRowId)
			}else{
				&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId,OEORI_Billed='I' where OEORI_rowid=:SubRowId)
			}
		}
		if SQLCODE {
			s err="-206"
			Quit
		}
		//调用医技接口位置放在医嘱状态改变之后，执行记录改变之前
		;调用服务总线接口
		s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(SubRowId,UserRowId,"2")
		
		s err=##Class(appcom.OEOrdExec).DiscontinueAll(SubRowId,UserRowId,StopFlag,IsBillN)
		if err Quit
		
		//撤销医嘱外部接口
		s err=..CancelOrdDocInterface(SubRowId,UserRowId)
	    if +err'=0 Quit
	    /*;调用服务总线接口
		s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(SubRowId,UserRowId)*/
		
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	TC
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  作废单条医嘱,长期医嘱或临时医嘱开立后因为某种原因不再有效而失效,
///               而且不需要在医嘱单上记录
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).UnUse("77075||1",127) 
ClassMethod UnUse(OrdItmRowId As %String, UserRowId As %String, ReasonDr As %String = "", ReasonDesc As %String = "", IsBillN As %String = "Y") As %String
{
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"							//医嘱不存在
	
	;1 调用计费接口 是拆账单的产生的自定价医嘱不可以停
	s ArcimRowId=$p($G(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1)),"^",2)
	s Rtn=##class(web.UDHCJFIntBill).JudgeArcIsorNot(ArcimRowId)
	if (Rtn=1){
		Q "-15304"
	}
	s OEORIChildsub=$o(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,""))
	if (OEORIChildsub'=""){
		 s mOrdItm=""
	}else{
		s mOrdItm=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),11)),"^",39)
	}
	//判断主医嘱跟关联医嘱是否在同一账单(只考虑未结算账单)
	s Rtn=##class(web.DHCBillInterface).ICheckBillIsSplit(OrdItmRowId,mOrdItm)
	if (Rtn="Y"){
		Q "-15307"
	}
	//实库库管进行了医嘱提取，需要经过高值材料库管员退货确认
	if ("Y"'=##class(web.DHCSTM.PCHCOLLSM).GetRetFlag(OrdItmRowId)) {
		q "-210"
	}
	if ..Executed(OrdItmRowId) Q "-302"
	if ##class(DHCDoc.DHCDocCure.Record).FindCureRecordByOEORI(OrdItmRowId)=1  Q "-15306"
	;set OEORIUserAdd=obj.OEORIUserAddGetObjectId()
	;if OEORIUserAdd'=UserRowId set err=-208 quit err   						//作废医嘱要和下医嘱人一致
	set OEORIUserAdd=""
	set DoctorDr = obj.OEORIDoctorDRGetObjectId()
	set:DoctorDr'="" OEORIUserAdd= $o(^SSU("SSUSR",0,"CTPCP",DoctorDr,""))
	if (OEORIUserAdd'="")&&(OEORIUserAdd'=UserRowId) set err=-208 quit err   		//12-06-02,作废医嘱要和下医嘱人一致
	set OEORIItemStatDR=obj.OEORIItemStatDR
	set OEORIItemStateCode=$s($IsObject(OEORIItemStatDR):OEORIItemStatDR.OSTATCode,1:"")
	set OEORIPlacerNo=obj.OEORIPlacerNo
	d obj.%Close()
	s obj=""
	
	if (OEORIItemStateCode'="V")&&(OEORIItemStateCode'="C")&&(OEORIItemStateCode'="I") Quit "-209"   //非核实状态的医嘱不能作废
	
	if OEORIPlacerNo'="" Quit "-207"

	s StatusRowId=$O(^OEC("OSTAT",0,"Code","U",0))
	
	s ret=..UpdateExtIfPractice(OrdItmRowId,UserRowId,StatusRowId)
	Q:ret'=0 ret
	TS
	s err=..UpdateStatus(OrdItmRowId,UserRowId,StatusRowId,ReasonDr,ReasonDesc)
	if err Tro  Q "-205"                            		//更新医嘱状态及变化表
       
	;如果没有停医嘱人(护士办理出院结算自动停医嘱),则取下医嘱人
	if UserRowId="" s UserRowId=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),7)),"^",1)
	&SQL(Select SSUSR_CareProv_DR into :DoctorRowId from SQLUser.SS_User where SSUSR_RowId=:UserRowId )
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)

	if DoctorRowId="" { 
		&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:OrdItmRowId)
	}else{
		&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:OrdItmRowId)
	}
	if SQLCODE TRo  Q "-206"
	
	;作废医嘱直接停止执行记录
	s err=##Class(appcom.OEOrdExec).DiscontinueAll(OrdItmRowId,UserRowId,1,IsBillN)    	//停止所有执行记录
	if err  Tro  Q err
	;s err=..CancelDoctorDischarge(OrdItmRowId,UserRowId)
	;if err'=0 Tro  Q err
	
	;停医嘱自动撤消治疗申请单
	;d ##class(DHCDoc.DHCDocCure.Apply).CancelCureApplyByStopOrd(OrdItmRowId,UserRowId)
	
	;调用服务总线接口
	s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(OrdItmRowId,UserRowId,"3")
	;非药理子类的检验检查药理项目需要撤销免费
	s PPRowID=$p($G(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),"DHC")),"^",10)
	if (PPRowID'=""){
		s err=##class(web.PilotProject.DHCDocPilotProject).CancelPPAOrdFree(PPRowID,OrdItmRowId,UserRowId)
		if err  Tro  Q err
	}
	;药房追踪接口
	/*if $d(^PHAPRESTRACKi("MOEORI",OrdItmRowId)) {
		s TrackLoc=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),7)),"^",2)
		d ##class(web.DHCINPHA.HMPresTrack.SqlDbPresTrack).HandlePresTrackDB(OrdItmRowId_"^"_""_"^"_""_"^"_"A3"_"^"_TrackLoc_"^"_UserRowId)
	}*/
	//撤销医嘱外部接口
	s err=..CancelOrdDocInterface(OrdItmRowId,UserRowId)
	if +err'=0  Tro  Q err
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId,ReasonDr,ReasonDesc)
		if err {
			s err="-205"
			Quit
		}
		
		if DoctorRowId="" { 
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:SubRowId)
		}else{
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:SubRowId)
		}
		
		s err=##Class(appcom.OEOrdExec).DiscontinueAll(SubRowId,UserRowId,1,IsBillN)
		if err Quit
		;s err=..CancelDoctorDischarge(SubRowId,UserRowId)
	    ;if err'=0 Quit
	    
	    ;停医嘱自动撤消治疗申请单
		;d ##class(DHCDoc.DHCDocCure.Apply).CancelCureApplyByStopOrd(SubRowId,UserRowId)
		//撤销医嘱外部接口
		s err=..CancelOrdDocInterface(SubRowId,UserRowId)
		if +err'=0  Quit
	
	    ;调用服务总线接口
	    s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(SubRowId,UserRowId)
		
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	//长期医生医嘱绑定的临时护嘱
	s Sub=$o(^OEORDi(0,"NUROEORI",OrdItmRowId,"I",0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId,ReasonDr,ReasonDesc)
		if err {
			s err="-205"
			Quit
		}
		if DoctorRowId="" { 
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:SubRowId)
		}else{
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:SubRowId)
		}
		s err=##Class(appcom.OEOrdExec).DiscontinueAll(SubRowId,UserRowId,1)
		if err Quit
		;s err=..CancelDoctorDischarge(SubRowId,UserRowId)
	    ;if err'=0 Quit
	    //撤销医嘱外部接口
		s err=..CancelOrdDocInterface(SubRowId,UserRowId)
		if +err'=0  Quit
	    ;调用服务总线接口
	    s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(SubRowId,UserRowId,"3")
		s Sub=$o(^OEORDi(0,"NUROEORI",OrdItmRowId,"I",Sub))
	}
    i err TRo  Q err
	TCommit
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.27
/// Description:  得到医嘱状态代码
/// Table:        OE_OrdItem,OEC_OrderStatus
/// Input:        OrdItmRowId:医嘱Rowid,
/// Return: 	  0:成功
/// OutPut:		  医嘱状态的代码
/// Others:       w ##class(appcom.OEOrdItem).GetStatusCode("77071||59") 
ClassMethod GetStatusCode(OrdItmRowId As %String) As %String
{
	s OEORIItemStatDR=$p(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1),"^",13)
	if OEORIItemStatDR="" Quit ""
	s OEORIItemStateCode=$p(^OEC("OSTAT",OEORIItemStatDR),"^",1)
	Quit OEORIItemStateCode
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  停止医嘱,将"未执行"的执行记录的医嘱状态上置"停止"，
/// 			  根据医院流程决定是否修改计费状态"B"变为"I","TB"变为"R"（调用计费设置）
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 	  0:成功
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).Stop("77078||44",127,"","75600") 
/// 
ClassMethod Stop(OrdItmRowId As %String, UserRowId As %String, ExpectEndDate As %Date, ExpectEndTime As %Time, StopAllExecFlag As %String = "", IsBillN As %String = "Y") As %String
{
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	
	
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"			   //医嘱不存在
	
	;1 调用计费接口 是拆账单的产生的自定价医嘱不可以停
	s ArcimRowId=$p($G(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1)),"^",2)
	s Rtn=##class(web.UDHCJFIntBill).JudgeArcIsorNot(ArcimRowId)
	if (Rtn=1){
		Q "-15304"
	}
	s OEORIChildsub=$o(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,""))
	if (OEORIChildsub'=""){
		 s mOrdItm=""
	}else{
		s mOrdItm=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),11)),"^",39)
	}
	//判断主医嘱跟关联医嘱是否在同一账单(只考虑未结算账单)
	s Rtn=##class(web.DHCBillInterface).ICheckBillIsSplit(OrdItmRowId,mOrdItm)
	if (Rtn="Y"){
		Q "-15307"
	}
	s OEORIItemStatDR=obj.OEORIItemStatDR
	s OEORIItemStateCode=$s($IsObject(OEORIItemStatDR):OEORIItemStatDR.OSTATCode,1:"")
	if (OEORIItemStateCode="D")&&(StopAllExecFlag'="1") Quit "-201"   //已经停止的医嘱不用再停
	if (OEORIItemStateCode="E") Quit "-203"   //已经执行的医嘱不能停止
	
	;临时类医嘱已经执行不能停止
	s PriorityDR=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),1)),"^",8)
	if ..ISShortOrderPrior(PriorityDR) {
		if ..Executed(OrdItmRowId) Q "-302"
	}
	s SttDate=obj.OEORISttDat
	s SttTime=obj.OEORISttTim
	s EndDate=obj.OEORIEndDate
	s EndTime=obj.OEORIEndTime	
	d obj.%Close()
	s obj=""
	
	;如果没有停医嘱人(护士办理出院结算自动停医嘱),则取下医嘱人
	if UserRowId="" s UserRowId=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),7)),"^",1)
	&SQL(Select SSUSR_CareProv_DR into :DoctorRowId from SQLUser.SS_User where SSUSR_RowId=:UserRowId )
	s err=0
	
	s StatusRowId=$O(^OEC("OSTAT",0,"Code","D",0))
	
	s ret=..UpdateExtIfPractice(OrdItmRowId,UserRowId,StatusRowId,ExpectEndDate)
	Q:ret'=0 ret
	TS
	
	if $g(ExpectEndDate)'="" {
		if ExpectEndTime="" s ExpectEndTime=CurrTime
		//预停时间大于本日则只更新预停时间
		if ExpectEndDate>CurrDate {
			&SQL(Update SQLUser.OE_OrdItem Set OEORI_EndDate=:ExpectEndDate,OEORI_EndTime=:ExpectEndTime,OEORI_UserUpdate=:UserRowId where OEORI_Rowid=:OrdItmRowId)
			if SQLCODE Tro  Q SQLCODE
			///增加预停时间日志
			&SQL(Insert into SQLUser.DHC_DocOrderPreStopLogin (DHCPreStop_Order,DHCPreStop_Date,DHCPreStop_Time,
			DHCPreStop_UpdateDate,DHCPreStop_UpdateTime,DHCPreStop_UpdateUser)Values (:OrdItmRowId,:ExpectEndDate,:ExpectEndTime
			,:CurrDate,:CurrTime,:UserRowId))
			if SQLCODE Tro  Q SQLCODE
			s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
			While (Sub'="") {
				s SubRowId=+OrdItmRowId_"||"_Sub
				;已经停止的医嘱不用再处理
				s SubStatusCode=..GetStatusCode(SubRowId) //||(SubStatusCode="U")
				//
				if (SubStatusCode="D")||(SubStatusCode="C")||(SubStatusCode="U") {
					s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
					continue
				}
	        	&SQL(Update SQLUser.OE_OrdItem Set OEORI_EndDate=:ExpectEndDate,OEORI_EndTime=:ExpectEndTime,OEORI_UserUpdate=:UserRowId where OEORI_Rowid=:SubRowId)
	        	if SQLCODE {
					s err="-202"      //更新预停时间
					Quit
				}
				///增加预停时间日志
				&SQL(Insert into SQLUser.DHC_DocOrderPreStopLogin (DHCPreStop_Order,DHCPreStop_Date,DHCPreStop_Time,
				DHCPreStop_UpdateDate,DHCPreStop_UpdateTime,DHCPreStop_UpdateUser)Values (:SubRowId,:ExpectEndDate,:ExpectEndTime
				,:CurrDate,:CurrTime,:UserRowId))
				if SQLCODE  {
					s err="-204"      //更新时间
					Quit
				}
				s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
			}
			i err TRo  Q err
			TC
			Quit 0
		}else{
			;如果传入的日期小于当前日期,会导致停止日期和需停长期医嘱的医嘱开始日期不一致
			;例如,当日开出院医嘱医嘱,将开始日期修改为昨天
			///增加预停时间日志
			&SQL(Insert into SQLUser.DHC_DocOrderPreStopLogin (DHCPreStop_Order,DHCPreStop_Date,DHCPreStop_Time,
			DHCPreStop_UpdateDate,DHCPreStop_UpdateTime,DHCPreStop_UpdateUser)Values (:OrdItmRowId,:ExpectEndDate,
			:ExpectEndTime,:CurrDate,:CurrTime,:UserRowId))
		}
			
	}
	if ExpectEndTime'="" s CurrTime=ExpectEndTime
	if ExpectEndDate'="" s CurrDate=ExpectEndDate
	/*小时医嘱停止提前到0点,退费会有问题,改到appcom.OEOrdExec.DiscontinueByXTime处理
	if (CurrTime=0)&&(##class(appcom.OEOrdItem).IsHourOrderItem(OrdItmRowId)) {
		s CurrTime=1
	}
	*/
	s StatusRowId=$O(^OEC("OSTAT",0,"Code","D",0))
	s err=..UpdateStatus(OrdItmRowId,UserRowId,StatusRowId)
	if err Tro  Q "-205"
	if DoctorRowId="" { 
		&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:OrdItmRowId)
	}else{
		&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:OrdItmRowId)
	}
	if SQLCODE TRo  Q "-206"
	s err=##Class(appcom.OEOrdExec).DiscontinueByXTime(OrdItmRowId,UserRowId,StopAllExecFlag,IsBillN)
	if err TRo  Q err
	
	;停医嘱自动撤消治疗申请单
	d ##class(DHCDoc.DHCDocCure.Apply).CancelCureApplyByStopOrd(OrdItmRowId,UserRowId)
	
	;调用服务总线接口
	s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(OrdItmRowId,UserRowId,"1")
	
	;药房追踪接口
	if $d(^PHAPRESTRACKi("MOEORI",OrdItmRowId)) {
		s TrackLoc=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),7)),"^",2)
		d ##class(web.DHCINPHA.HMPresTrack.SqlDbPresTrack).HandlePresTrackDB(OrdItmRowId_"^"_""_"^"_""_"^"_"A3"_"^"_TrackLoc_"^"_UserRowId)
	}	
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		;已经停止的医嘱不用再处理
		s SubStatusCode=..GetStatusCode(SubRowId)
		//if SubStatusCode="D" { ||(SubStatusCode="U")
		//加上U，防止护士作废后，医生再停止医嘱更新掉状态
		if (SubStatusCode="D")||(SubStatusCode="C")||(SubStatusCode="U") {
			s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
			continue
		}
		s err=..UpdateStatus(SubRowId,UserRowId,StatusRowId)
		if err {
			s err="-205"
			Quit
		}
		if $g(DoctorRowId)="" { 
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime where OEORI_rowid=:SubRowId)
		}else{
			&SQL(Update SQLUser.OE_OrdItem set OEORI_Xdate=:CurrDate,OEORI_Xtime=:CurrTime,OEORI_XCTCP_DR=:DoctorRowId where OEORI_rowid=:SubRowId)
		}
		if SQLCODE {
			s err="-206"
			Quit
		}
		s err=##Class(appcom.OEOrdExec).DiscontinueByXTime(SubRowId,UserRowId,StopAllExecFlag,IsBillN)
		if err Quit
		
		;停医嘱自动撤消治疗申请单
		d ##class(DHCDoc.DHCDocCure.Apply).CancelCureApplyByStopOrd(SubRowId,UserRowId)
		;调用服务总线接口
		s rtn=##class(DHCDoc.Interface.Inside.Invoke).CancelOrdInterface(SubRowId,UserRowId,"1")
		
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	TC
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  更新医嘱状态,并插入医嘱状态变化表
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).UpdateStatus("531546||1",590) 
ClassMethod UpdateStatus(OrdItmRowId As %String, UserRowId As %String, StatusRowId As %String, ReasonDr As %String = "", ReasonDesc As %String = "") As %String
{

	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	TS
	&sql(Update SQLUser.OE_OrdItem set OEORI_ItemStat_DR=:StatusRowId where OEORI_RowId=:OrdItmRowId)
	if SQLCODE TRollback  q SQLCODE
	
	&sql(insert into SQLUser.OE_OrdStatus (ST_ParRef,ST_Date,ST_Time,ST_Status_DR,ST_User_DR)
	values (:OrdItmRowId,:CurrDate,:CurrTime,:StatusRowId,:UserRowId))
	if SQLCODE TRollback  q SQLCODE
	//更新撤下/作废原因
	s STRowId=$p(%ROWID,$c(1))
	s objstatus=##class(User.OEOrdStatus).%OpenId(STRowId)
	if (ReasonDr'="") d objstatus.STReasonDRSetObjectId(ReasonDr)
	e  i ReasonDesc'="" s objstatus.STReasonComtent=ReasonDesc
	s sc=objstatus.%Save()
	If $$$ISERR(sc) Tro  Quit "-3077"
    d objstatus.%Close()
    s objstatus=""
    
	TC
	Q SQLCODE
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  停止医嘱处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针,PWFlag:是否密码验证,PinNum:明文密码
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).StopMulti("531546||1",590,"") 
ClassMethod StopMulti(OrdList As %String = "", UserID As %String = "", PinNum As %String, PWFlag As %String = "Y")
{
	s ^TEMP("Debug","StopMulti")="w ##class(appcom.OEOrdItem).StopMulti("""_OrdList_""","""_UserID_""","""_PinNum_""","""_PWFlag_""")"
	s adm=$$GetAdmByOrdList(OrdList)
	s PAADMType=$p($g(^PAADM(adm)),"^",2)
	if PAADMType'="I" {
		s OrdList=$tr(OrdList,"!","&")
		Q ##class(web.UDHCStopOrderLook).StopOrder("","",OrdList,UserID,PinNum,PWFlag)
	}
	
	;密码验证
	s err=0
 	if PWFlag="Y" s err=##Class(web.DHCOEOrdItem).PinNumberValid(UserID,PinNum)
	Q:err'=0 err

 	;需要控制执行的医嘱优先级
 	s CFStopExecOrderPriorStr=##Class(web.DHCDocConfig).GetConfigNode("StopExecOrderPrior")
 	if CFStopExecOrderPriorStr'="" s CFStopExecOrderPriorStr="^"_CFStopExecOrderPriorStr_"^"
 	s Hospital=##Class(web.DHCDocConfig).GetConfigNode("CurrentHospital")
	s HospitalCode=$P(Hospital,"^",1)

 	;重新组织停医嘱串,根据配置停主医嘱
 	s StopGroupOrder=##Class(web.DHCDocConfig).GetConfigNode("StopGroupOrder")
 	s OrdListStr=""
 	s Len=$l(OrdList,"^")
 	for i=1:1:Len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)    //不能改医嘱ID为第一位的位置
		s EndDate=$p(OrderItemStr,"!",2)
		s EndTime=$p(OrderItemStr,"!",3)
		;不必从界面取的关联医嘱RowId   zhouzq 2010.07.21
		s OrdLinkRowId=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),11)),"^",39)
		;add by zhouzq 2012.06.08
		s SingleStopFlag=..CheckSingleStop(oeitm,UserID)
		if SingleStopFlag'=1 {
			if (StopGroupOrder=1){
				;如果确认成组停止,子医嘱RowId不需要传了
				if (OrdLinkRowId'="") {
					if (OrdListStr'[(OrdLinkRowId_"!")){
						 s OrderItemStr=OrdLinkRowId_"!"_EndDate_"!"_EndTime
					}else{
						continue
					}
				}else{
					if (OrdListStr[(oeitm_"!")){
						continue
					}
				}
			}else{
				;如果已经选择了子医嘱,子医嘱RowId不需要传了
				if (OrdLinkRowId'="")&&(OrdListStr[(OrdLinkRowId_"!")) continue
			}
		}
		if OrdListStr="" s OrdListStr=OrderItemStr
		else  s OrdListStr=OrdListStr_"^"_OrderItemStr
	}
	s adm=""
 	s err=0
 	s OrdList=OrdListStr
 	s len=$l(OrdList,"^")
	for i=1:1:len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)
		s EndDate=$p(OrderItemStr,"!",2)
		s EndTime=$p(OrderItemStr,"!",3)
		s EndDate=$s(EndDate="":+$H,1:$zdh(EndDate,##class(websys.Conversions).DateFormat()))
		s EndTime=$s(EndTime="":$p($H,",",2),1:$zth(EndTime))	;wanghc
		
		//当天执行记录强制停止子类
		s itemrowid=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),1)),"^",2)
		s ItemCatRowId=+$p($g(^ARCIM(+$g(itemrowid),1,1)),"^",10)
		s StopAllExecItemCat=$g(^DHCDocConfig("StopAllExecItemCat"))
		s StopAllExecFlag=0
		i ("^"_StopAllExecItemCat_"^")[("^"_ItemCatRowId_"^") s StopAllExecFlag=1
		
		s err=..Stop(oeitm,UserID,EndDate,EndTime,StopAllExecFlag,"N")
		s adm=$p(^OEORD(+oeitm),"^",1)
	 }
	 Q:err'=0 err
	 //s rtn=##Class(web.DHCAntCombined).StopAntOrder(adm,OrdList)
	 s rtn=##Class(DHCAnt.KSS.Combined).StopAntOrder(adm,OrdList)
	 s rtn=##Class(web.UDHCJFBILL).BILLN(adm,UserID,"")
	 /*集成平台接口
	 Set OrdList=##class(DHCIntergration.Common.Method.Base).ReplaceStr(OrdList,"&&","^")
	 d ##class(web.DHCBL.CI.ServiceBuilder).OPOEORIService("OPCRefund",OrdList)
	 */
	 q err
GetAdmByOrdList(OrdListStr)
	s adm=""
	s len=$l(OrdListStr,"^")
	for i=1:1:len {
		s OrderItemStr=$p(OrdListStr,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)
		continue:oeitm=""
		s adm=$p(^OEORD(+oeitm),"^",1)
		quit
	 }
	 Q adm
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  撤销医嘱处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).CancelMulti("77078||17",127,"N","N") 
ClassMethod CancelMulti(OrdList As %String, UserID As %String, PinNum As %String, PWFlag As %String = "Y", ReasonDr As %String = "", ReasonDesc As %String = "") As %String
{
	s ^TEMP("Debug","CancelMulti")="w ##class(appcom.OEOrdItem).CancelMulti("""_OrdList_""","""_UserID_""","""_PinNum_""","""_PWFlag_""","""_ReasonDr_""","""_ReasonDesc_")"
	Q:($g(OrdList)="")||($g(UserID)="") -100
	
	s err=0
	;密码验证
 	if PWFlag="Y" s err=##Class(web.DHCOEOrdItem).PinNumberValid(UserID,PinNum)
	Q:err'=0 err
	
 	;重新组织停医嘱串,根据配置停主医嘱
 	s StopGroupOrder=##Class(web.DHCDocConfig).GetConfigNode("StopGroupOrder")
 	/*s OrdListStr=""
 	k OrdPLIST
	s ItemPar=""
	for i=1:1:$l(OrdList,"^") {
		set OrderItemStr=$p(OrdList,"^",i)
		set oeitm=$p(OrderItemStr,"!",1)
		if oeitm="" Continue
		set ItemPar=+oeitm
		s OrdLinkRowId=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),11)),"^",39)
		;add by zhouzq 2012.06.08
		s SingleStopFlag=..CheckSingleStop(oeitm,UserID)
		if SingleStopFlag'=1 {
			; 改成OrdPLIST数组 wanghc 2014-12-15
			//if (StopGroupOrder=1)&&(OrdLinkRowId'="")&&(OrdList'[(OrdLinkRowId_"!")) s OrderItemStr=OrdLinkRowId
			if (StopGroupOrder=1){
				;如果确认成组停止,子医嘱RowId不需要传了
				if (OrdLinkRowId'="") {
					Set OrdPLIST(OrdLinkRowId)=oeitm
				}else{
					Set OrdPLIST(oeitm)=oeitm				
				}
			}else{
				;如果已经选择主医嘱,子医嘱RowId不需要传了
				;if (OrdLinkRowId'="")&$d(OrdPLIST(OrdLinkRowId)) continue
				if (OrdLinkRowId'=""){
					if $d(OrdPLIST(OrdLinkRowId)) continue
				}
				Set OrdPLIST(oeitm)=oeitm
			}
		}
	}	
	Set adm="", oeitm="",err=0
	For  Set oeitm=$o(OrdPLIST(oeitm))  Quit:oeitm=""   Set err=..Cancel(oeitm,UserID) quit:(err'=0)*/
	s ItemPar=""
    s OrdListStr=""
	for i=1:1:$l(OrdList,"^") {
		set OrderItemStr=$p(OrdList,"^",i)
		set oeitm=$p(OrderItemStr,"!",1)
		if oeitm="" Continue
		set ItemPar=+oeitm
		s OrdLinkRowId=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),11)),"^",39)
		;add by zhouzq 2012.06.08
		s SingleStopFlag=..CheckSingleStop(oeitm,UserID)
		if SingleStopFlag'=1 {
			//if (StopGroupOrder=1)&&(OrdLinkRowId'="")&&(OrdList'[(OrdLinkRowId_"!")) s OrderItemStr=OrdLinkRowId
			if (StopGroupOrder=1){
				;如果确认成组停止,子医嘱RowId不需要传了
				if (OrdLinkRowId'="") {
					//if (OrdListStr'[(OrdLinkRowId_"!")) {
					if (("^"_OrdListStr_"^")'[("^"_OrdLinkRowId_"^")) {
						s OrderItemStr=OrdLinkRowId
					}else{
						continue
					}
				}else{
					//if (OrdListStr[(oeitm_"!")){
					if (("^"_OrdListStr_"^")[("^"_oeitm_"^")){
						continue
					}	
				}
			}else{
				;如果已经选择了子医嘱,子医嘱RowId不需要传了
				//if (OrdLinkRowId'="")&&(OrdListStr[(OrdLinkRowId_"!")) continue
				if (OrdLinkRowId'="")&&(("^"_OrdListStr_"^")[("^"_OrdLinkRowId_"^")) continue
			}
		}
		if OrdListStr="" s OrdListStr=OrderItemStr
		else  s OrdListStr=OrdListStr_"^"_OrderItemStr

	 }
	s AppendOrdListStr=##Class(web.UDHCStopOrderLook).GetLabAppenOrdInfo(OrdListStr)
	if (AppendOrdListStr'=""){
		s OrdListStr=OrdListStr_"^"_AppendOrdListStr
	}
	//多科会诊申请产生的多条医嘱需要同时撤销/作废
	s AppendOrdListStr=..GetCstRelOeori(OrdListStr)
	if (AppendOrdListStr'=""){
		s OrdListStr=OrdListStr_"^"_AppendOrdListStr
	}
	s adm=""
 	s err=0
 	s OrdList=OrdListStr
 	k TempCancelMulOEItem($j)
 	s len=$l(OrdList,"^")
	for i=1:1:len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)
		continue:$d(TempCancelMulOEItem($j,oeitm))
		s err=..Cancel(oeitm,UserID,ReasonDr,ReasonDesc,"N")
		s adm=$p(^OEORD(+oeitm),"^",1)
		s TempCancelMulOEItem($j,oeitm)=1
	 }
	 k TempCancelMulOEItem($j)
	Quit:(err'=0) err
	i ItemPar'="" {
		Set adm=$p(^OEORD(ItemPar),"^",1)	
		Set rtn=##Class(web.UDHCJFBILL).BILLN(adm,UserID,"")
		//抗生素联用撤销医嘱
		//s antrtn=##class(web.DHCAntCombined).StopAntOrder(adm,OrdList)  
		s antrtn=##class(DHCAnt.KSS.Combined).StopAntOrder(adm,OrdList)  
	}
	Quit err
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  作废医嘱处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).UnUseMultir("147||27",4634,"1","Y") 
ClassMethod UnUseMulti(OrdList As %String, UserID As %String, PinNum As %String, PWFlag As %String = "Y", ReasonDr As %String = "", ReasonDesc As %String = "") As %String
{
	s ^TEMP("Debug","UnUseMulti")="w ##class(appcom.OEOrdItem).UnUseMulti("""_OrdList_""","""_UserID_""","""_PinNum_""","""_PWFlag_""")"
	Q:($g(OrdList)="")||($g(UserID)="") -100
	
	s err=0
	;密码验证
 	if PWFlag="Y" s err=##Class(web.DHCOEOrdItem).PinNumberValid(UserID,PinNum)
	Q:err'=0 err
	
 	;重新组织停医嘱串,根据配置停主医嘱
 	s StopGroupOrder=##Class(web.DHCDocConfig).GetConfigNode("StopGroupOrder")
 	s OrdListStr=""
	for i=1:1:$l(OrdList,"^") {
		set OrderItemStr=$p(OrdList,"^",i)
		set oeitm=$p(OrderItemStr,"!",1)
		if oeitm="" Continue
		s OrdLinkRowId=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),11)),"^",39)
		;add by zhouzq 2012.06.08
		s SingleStopFlag=..CheckSingleStop(oeitm,UserID)
		if SingleStopFlag'=1 {
			//if (StopGroupOrder=1)&&(OrdLinkRowId'="")&&(OrdList'[(OrdLinkRowId_"!")) s OrderItemStr=OrdLinkRowId
			if (StopGroupOrder=1){
				;如果确认成组停止,子医嘱RowId不需要传了
				if (OrdLinkRowId'="") {
					//if (OrdListStr'[(OrdLinkRowId_"!")) {
					if (("^"_OrdListStr_"^")'[("^"_OrdLinkRowId_"^")) {
						s OrderItemStr=OrdLinkRowId
					}else{
						continue
					}
				}else{
					//if (OrdListStr[(oeitm_"!")){
					if (("^"_OrdListStr_"^")[("^"_oeitm_"^")){
						continue
					}	
				}
			}else{
				;如果已经选择了子医嘱,子医嘱RowId不需要传了
				//if (OrdLinkRowId'="")&&(OrdListStr[(OrdLinkRowId_"!")) continue
				if (OrdLinkRowId'="")&&(("^"_OrdListStr_"^")[("^"_OrdLinkRowId_"^")) continue
			}
		}

		
		if OrdListStr="" s OrdListStr=OrderItemStr
		else  s OrdListStr=OrdListStr_"^"_OrderItemStr
    }
	s AppendOrdListStr=##Class(web.UDHCStopOrderLook).GetLabAppenOrdInfo(OrdListStr)
	if (AppendOrdListStr'=""){
		s OrdListStr=OrdListStr_"^"_AppendOrdListStr
	}
	//多科会诊申请产生的多条医嘱需要同时撤销/作废
	s AppendOrdListStr=..GetCstRelOeori(OrdListStr)
	if (AppendOrdListStr'=""){
		s OrdListStr=OrdListStr_"^"_AppendOrdListStr
	}
	s adm=""
 	s err=0
 	s OrdList=OrdListStr
 	s len=$l(OrdList,"^")
 	k TempUnUserMulOEItem($j)
	for i=1:1:len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)
		continue:$d(TempUnUserMulOEItem($j,oeitm))
		s err=..UnUse(oeitm,UserID,ReasonDr,ReasonDesc,"N")
		s adm=$p(^OEORD(+oeitm),"^",1)
		s TempUnUserMulOEItem($j,oeitm)=1
	 }
	 k TempUnUserMulOEItem($j)
	 Q:err'=0 err
	 s rtn=##Class(web.UDHCJFBILL).BILLN(adm,UserID,"")
	 //抗生素联用作废医嘱
	 //s antrtn=##class(web.DHCAntCombined).CancleAntOrder(adm,OrdList)
	 s antrtn=##class(DHCAnt.KSS.Combined).CancleAntOrder(adm,OrdList)   
	 Q err
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  判断是否为小时类医嘱,这类医嘱执行记录里一天只插入一条
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).IsHourOrderItem("77067||9") 
ClassMethod IsHourOrderItem(OrderItemRowId As %String) As %String
{
	s ArcimRowId=$p(^OEORD(+OrderItemRowId,"I",$P(OrderItemRowId,"||",2),1),"^",2)
	s BillUomRowId=$p($g(^ARCIM(+ArcimRowId,$p(ArcimRowId,"||",2),8)),"^",14)
	s BillUomCode=""
	s:+BillUomRowId'=0 BillUomCode=$p($g(^CT("UOM",BillUomRowId)),"^")
	s BillUomCode=$zcvt($g(BillUomCode),"U")
	Q:BillUomCode="HOUR" 1
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否为长期医嘱类型
/// Table:        OEC_OrderPriority
/// Input:        PriorRowId:医嘱类型指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).ISLongOrderPrior("77067||9") 
ClassMethod ISLongOrderPrior(PriorRowId As %String)
{
	q:PriorRowId="" 0
	s PriorCode=$p($g(^OECPR(PriorRowId)),"^")
	if (PriorCode="S")||(PriorCode="OMST")||(PriorCode="OMCQZT") {
		Q 1
	}
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否为不发药医嘱
/// Table:        OEC_OrderPriority
/// Input:        PriorRowId:医嘱类型指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).ISUnDspOrderPrior("1") 
ClassMethod ISUnDspOrderPrior(PriorRowId As %String)
{
	i PriorRowId="" Q 0
	s PriorCode=$p($g(^OECPR(PriorRowId)),"^",1)
	if (PriorCode="OM")||(PriorCode="OMST") Q 1
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否为临时类医嘱
/// Table:        OEC_OrderPriority
/// Input:        PriorRowId:医嘱类型指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).ISShortOrderPrior("1") 
ClassMethod ISShortOrderPrior(PriorRowId As %String, OrderPriorType As %String = "")
{
	i PriorRowId="" Q 0
	s PriorCode=$p($g(^OECPR(PriorRowId)),"^",1)
	;Q '..ISLongOrderPrior(PriorCode)
	//if (PriorCode="OM")||(PriorCode="NORM")||(PriorCode="STAT")||(PriorCode="OUT")||(PriorCode="ONE")||(PriorCode="OMLSZT") Q 1
	if (OrderPriorType="OutOrderPrior"){
		if (PriorCode="OUT") Q 1
		Q 0
	}elseif(OrderPriorType="ShortOrderPrior"){
		if (PriorCode="OM")||(PriorCode="NORM")||(PriorCode="STAT")||(PriorCode="ONE")||(PriorCode="OMLSZT") Q 1
		Q 0
	}else{
		if (PriorCode="OM")||(PriorCode="NORM")||(PriorCode="STAT")||(PriorCode="OUT")||(PriorCode="ONE")||(PriorCode="OMLSZT") Q 1
	}
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否为PRN医嘱(长期)
/// Table:        OEC_OrderPriority
/// Input:        PriorRowId:医嘱类型指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).ISPRNOrder("77067||9") 
ClassMethod ISPRNOrder(OrdItmRowId As %String) As %String
{
	s PHFreqDr = $p(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),2),"^",4)	;频次 OEORI_PHFreq_DR
	s PHFreqCode=$s(PHFreqDr'="":$p(^PHCFR(PHFreqDr),"^",1),1:"")
	i $ZCVT(PHFreqCode,"U")="PRN" Q 1
	Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否此医嘱的执行记录是否已执行过收费
/// Table:        OEC_OrderPriority
/// Input:        PriorRowId:医嘱类型指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).Executed("1") 
ClassMethod Executed(OrdItmRowId As %String) As %String
{
	&SQL(Select count(*) into :execsum from SQLUser.OE_OrdExec 
		  Where OEORE_OEORI_PARREF=:OrdItmRowId and 
				(OEORE_Order_Status_DR->STAT_Code='F' or OEORE_Billed='P') )
	if execsum>0 {
		Quit 1
	}
	Q 0
}

/// creator:	郭荣勇
/// date:		2015-11-24
/// desc:		判断就诊在某日期和时间之后是否有已经执行的执行记录
/// Table:      OE_OrdItem,OE_OrdExec
/// Input:      OEORIRowId:执行记录指针
/// Return: 
/// OutPut:	
/// w ##class(appcom.OEOrdItem).CheckIsExistExecByDateT("285||49","2018-11-07","15:00")
ClassMethod CheckIsExistExecByDateT(OEORIRowId As %String, CheckDate As %String, CheckTime As %String) As %String
{
	s ret=1,stopMsg="",firstExecId=""
	Q:(OEORIRowId="")||(CheckDate="") ret_"^"_stopMsg_"^"_firstExecId
	
	s oeori=$p(OEORIRowId,"||",1)
	s oeorisub=$p(OEORIRowId,"||",2)
	
	//当天执行记录强制停止子类,不进行是否执行的判断
	s itemrowid=$p($g(^OEORD(+oeori,"I",oeorisub,1)),"^",2)
	s ItemCatRowId=+$p($g(^ARCIM(+$g(itemrowid),1,1)),"^",10)
	s StopAllExecItemCat=$g(^DHCDocConfig("StopAllExecItemCat"))
	s StopAllExecFlag=0
	i ("^"_StopAllExecItemCat_"^")[("^"_ItemCatRowId_"^") s StopAllExecFlag=1
	Q:StopAllExecFlag=1 ret_"^"_stopMsg_"^"_firstExecId
	
	i $l(CheckDate,"/")=3 s CheckDate = $zdh(CheckDate,4)
	i $l(CheckDate,"-")=3 s CheckDate = $zdh(CheckDate,3)
	i CheckTime[":" s CheckTime=$zth(CheckTime)
	s FreqRowid=$P($G(^OEORD(oeori,"I",oeorisub,2)),"^",4)
	if (FreqRowid=""){
		;无频次医嘱,判断护士执行时间在ExpectEndDate之后有已执行的执行记录,不允许停止
		s tmpdate=CheckDate-1
		for {
			s tmpdate=$o(^OEORDi(0,"DateExecute",tmpdate))
			Quit:tmpdate=""
			s xSub=0
			for {
				set xSub = $o(^OEORDi(0,"DateExecute",tmpdate,oeori,oeorisub,xSub))
				Quit:xSub=""
				s ExecId=oeori_"||"_oeorisub_"||"_xSub
				Set str = $g(^OEORD(oeori,"I",oeorisub,"X",xSub))
				set ExecStateDR = $p(str,"^",16)
				Continue:ExecStateDR=""
				Set ExecStateCode = $p(^OEC("STAT",ExecStateDR),"^",1)
				if (ExecStateCode="F")&&(tmpdate>CheckDate) set ret=0,stopMsg="-15305",firstExecId=ExecId
				set tmptime = $p(str,"^",20)
				if (ExecStateCode="F")&&(tmpdate=CheckDate)&&(tmptime>CheckTime)  set ret=0,stopMsg="-15305",firstExecId=ExecId
				Quit:ret=0
			}
			Quit:ret=0
		}
	}else{
		;ExpectEndDate之后有执行记录已执行，不允许停止
		s maxExDate = $o(^OEORDi(0,"OrdItem",oeori,oeorisub,""),-1)
		for tmpdate = CheckDate:1:maxExDate {
			set xSub=0 
			for  {
				set xSub = $o(^OEORDi(0,"OrdItem",oeori,oeorisub,tmpdate,xSub)) 
				Quit:xSub=""
				s ExecId=oeori_"||"_oeorisub_"||"_xSub
				Set str = $g(^OEORD(oeori,"I",oeorisub,"X",xSub))
				set ExecStateDR = $p(str,"^",16)
				Continue:ExecStateDR=""
				Set ExecStateCode = $p(^OEC("STAT",ExecStateDR),"^",1)
				if (ExecStateCode="F")&&(tmpdate>CheckDate) set ret=0,stopMsg="-15305",firstExecId=ExecId
				set tmptime = $p(str,"^",2)
				if (ExecStateCode="F")&&(tmpdate=CheckDate)&&(tmptime>CheckTime)  set ret=0,stopMsg="-15305",firstExecId=ExecId
				Quit:ret=0
			}
			Quit:ret=0
		}
	}
	
	
	Q:ret=0 "0^"_stopMsg_"^"_firstExecId
	
	Q ret_"^"_stopMsg_"^"_firstExecId
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否此医嘱是否可以单独停止医生开出的非医嘱单医嘱,护士可以停止护士开出的子医嘱
/// Table:        OEC_OrderPriority
/// Input:        OrderItemRowId:医嘱指针,UserRowId:登录用户指针
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).CheckSingleStop("38||2","127") 
ClassMethod CheckSingleStop(OrderItemRowId As %String, UserRowId As %String) As %Boolean
{
	s OrdLinkRowId=$p($g(^OEORD(+OrderItemRowId,"I",$p(OrderItemRowId,"||",2),11)),"^",39)
	if OrdLinkRowId="" Q 0
	
	s DoctorDr=$P(^SSU("SSUSR",UserRowId),"^",14)	
	Q:DoctorDr="" 0
	
	s CTPCPCarPrvTpDR = $p(^CTPCP(DoctorDr,1),"^",4)
	s CTCPTInternalType = $p(^CT("CPT",CTPCPCarPrvTpDR),"^",4)
	
	s MasterDoctorDr=$P($G(^OEORD(+OrderItemRowId,"I",$P(OrderItemRowId,"||",2),1)),"^",11)	
	Q:MasterDoctorDr="" 0
	
	s CTPCPCarPrvTpDR = $p(^CTPCP(MasterDoctorDr,1),"^",4)
	s MasterCTCPTInternalType = $p(^CT("CPT",CTPCPCarPrvTpDR),"^",4)
	
	//如果是护士录入绑定的子医嘱，护士停止时需停止整组医嘱
	s OrdBindSource=$p($g(^OEORD(+OrderItemRowId,"I",$p(OrderItemRowId,"||",2),"DHC")),"^",41)
	if (OrdBindSource'="")&&(MasterCTCPTInternalType="NURSE") Q 0
	
    if (MasterCTCPTInternalType="DOCTOR")&&(CTCPTInternalType="NURSE"){
		s ItmMastDR = $p($g(^OEORD(+OrderItemRowId,"I",$p(OrderItemRowId,"||",2),1)),"^",2)
		s mastItemCat = $p(^ARCIM(+ItmMastDR,$p(ItmMastDR,"||",2),1),"^",10)			;护士站配置 子类		
		if $g(^DHCOEOrdPrintSet("NotSordCat"))[("^"_mastItemCat_"^") q 1
		s arcicOrdCatDR = $p(^ARC("IC",mastItemCat),"^",8)								;护士站配置 大类
		if $g(^DHCOEOrdPrintSet("NotOrdCat"))[("^"_arcicOrdCatDR_"^") q 1
    }
    if (MasterCTCPTInternalType="NURSE")&&(CTCPTInternalType="NURSE") q 1
    Q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.19
/// Description:  判断是否此医嘱是否可以停止
/// Table:        OEC_OrderPriority
/// Input:        OrderItemRowId:医嘱指针,UserRowId:登录用户指针,LocID:登录科室,GroupID:登录安全组
/// Return: 
/// OutPut:		  1:是,0:否
/// Others:       w ##class(appcom.OEOrdItem).CheckStopPermission("1") 
ClassMethod CheckStopPermission(OrderItemRowId As %String, UserRowId As %String, LocID As %String, GroupID As %String = "") As %String
{
	s ^TEMP("Debug","CheckStopPermission")="w ##class(appcom.OEOrdItem).CheckStopPermission("""_OrderItemRowId_""","""_UserRowId_""","""_LocID_""","""_GroupID_""")"

	;s AddUserRowId=$P($G(^OEORD(+OrderItemRowId,"I",$P(OrderItemRowId,"||",2),7)),"^",1)
	;s DoctorDr=$P(^SSU("SSUSR",AddUserRowId),"^",14)
	;Q:DoctorDr="" 0
	s DoctorDr=$P($G(^OEORD(+OrderItemRowId,"I",$P(OrderItemRowId,"||",2),1)),"^",11)	
	Q:DoctorDr="" 1
	
	if $d(^RB("RES",0,"CTPCP",DoctorDr,LocID)) s ret=1 q ret
	s ret=0,isNurse=0
	s ctpcprowid=$P(^SSU("SSUSR",UserRowId),"^",14)
	s CTPCPCarPrvTpDR = $p(^CTPCP(ctpcprowid,1),"^",4)
	s CTCPTInternalType = $p(^CT("CPT",CTPCPCarPrvTpDR),"^",4)
	s:CTCPTInternalType="NURSE" isNurse=1
	s oeori = ++OrderItemRowId
	s oeorisub = $P(OrderItemRowId,"||",2)
	
	if isNurse=1 d
	.;if $d(^RB("RES",0,"CTPCP",DoctorDr,LocID)) s ret=1 q
	.;else  d
	.;护士可以单独停医生开出的绑定其他医嘱的非医嘱单医嘱
	.s currLocId=","_LocID_","
	.s id=0 f  s id=$o(^CTLOC(id)) q:id=""  d
	..i $d(^CTLOC(id,"LINK",0,"Loc",LocID))=10 s currLocId=currLocId_id_","
	.s ordDept = $p($g(^OEORD(oeori,"I",oeorisub,7)),"^",2)	;OEORI_UserDepartment_DR
	.q:currLocId'[ordDept		;转科医嘱不能停
	.q:'$d(^OEORD(oeori,"I",oeorisub,11))
	.s oriOriDr=$p(^OEORD(oeori,"I",oeorisub,11),"^",39)
	.q:oriOriDr=""				;非子嘱不能停
	.s str1 = ^OEORD(oeori,"I",oeorisub,1)
	.s ItmMastDR = $p(str1,"^",2)
	.s mastItemCat = $p(^ARCIM(+ItmMastDR,$p(ItmMastDR,"||",2),1),"^",10)			;护士站配置 子类		
	.s:$g(^DHCOEOrdPrintSet("NotSordCat"))[("^"_mastItemCat_"^") ret=1	q
	.s arcicOrdCatDR = $p(^ARC("IC",mastItemCat),"^",8)								;护士站配置 大类
	.s:$g(^DHCOEOrdPrintSet("NotOrdCat"))[("^"_arcicOrdCatDR_"^") ret=1 q

	q ret
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  插入多条医嘱处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        Adm:就诊指针,OrdItemStr:医嘱信息串,User:用户指针,Loc:录入科室,Doc:医嘱所属医护人员
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).InsertMulti() 
/// 				  OrdItemStr描述:
/// 				医嘱项指针 ^医嘱项类型^ 医嘱类型指针 ^ 开始日期 ^ 开始时间 ^整包装数^自定义价格^ 接收科室指针
/// 				费别指针^剂型指针^备注^ 剂量 ^ 剂量单位指针 ^总剂量^ 频次指针 ^疗程指针^用法指针^处方类型^主医嘱序号^ 医嘱序号
/// 				皮试标志^草药用法^医保内标志^皮试液类型^医嘱套指针^结束日期^结束时间^执行日期串^紧急标志
/// 				诊断分类指针^长嘱首日次数^症状^输液流速^麻醉申请单ID^检验号^ 关联医嘱指针 ^营养药标志^材料条码
/// 				临床路径项目指针^医保审批类型
ClassMethod InsertMulti(Adm As %String, OrdItemStr As %String, User As %String, Loc As %String, Doc As %String) As %Status
{
	s ^TEMP("Debug","InsertMultiple1")="w $$InsertMultiple^DHCDocOrderCommonNew("_Adm_","""_OrdItemStr_""","_User_","_Loc_","_Doc_",""LABDATA"")"

	Set Config=##Class(websys.Configuration).%OpenId(1)
	Set MEDDATA=Config.DataNamespace
	Set LABDATA=Config.LabDataNamespace
	s PAADMType=$p($g(^PAADM(Adm)),"^",2)
	if PAADMType="I" {
		Set Ret=$$InsertMultiple^DHCDocOrderCommonNew(Adm,OrdItemStr,User,Loc,Doc,LABDATA)
	}else{
		Set CurrentNS=$ZNSPACE
		ZN MEDDATA		
		Set Ret=$$InsertMultiple^DHCDocOrderCommon(Adm,OrdItemStr,User,Loc,Doc,LABDATA)
		ZN CurrentNS
	}
	
	s $ZT="BIllERROR"
	If (Ret'=0)&&(Ret'=100){
		//如果设置了押金控制,需要做帐单
		s PAADMType=$p($g(^PAADM(Adm)),"^",2)
		s BillAfterUpdate=##Class(web.DHCDocConfig).GetConfigNode("CheckIPDeposit")
		if PAADMType="I",BillAfterUpdate="1" s rtn=##Class(web.UDHCJFBILL).BILLN(Adm,User,"")

		//插入医嘱时自动插入临床路径实施记录
		Do ##class(web.DHCCPW.MR.Interface).InsertDHCCPWImp(Adm,Ret,User,Doc)
	}
	
	///调用RIS接口, 把医嘱信息发送给RIS  add by gongping 2010-12-28
	///s ret=##class(RISService.InvokeRISService).SendIPOrditemInfoToRIS(Ret)
	
	///调用平台接口，把医嘱信息插入平台医嘱中间表 yiwenjun 2012-02-15
	///d ##class(DHCENS.NURSE.SOAPSfInfoService).GetOrderRowId(Ret)

	QUIT Ret
BIllERROR
	Quit -1_"^"_Ret
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  插入单条条医嘱处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        par:医嘱主表执行,udf:验证参数,PLIST:医嘱信息数组,同User.OEOrdItem的字段ColumnNumber
/// Return: 
/// OutPut:		  0:成功
/// Others:       w ##class(appcom.OEOrdItem).Insert() 
ClassMethod Insert(par As %String, udf As %String, ByRef PLIST) As %String
{
	;call UDF for validation
	s udf=$g(udf)
	s udf1=$p(udf,"^"),udf2=$p(udf,"^",2),ExecuteDateStr=$p(udf,"^",3),OrderNeedPIVAFlag=$p(udf,"^",4)
	s udf=udf1
	s PLIST(0)=par
	i udf["Y" s err=$$valid^MVBSSVAL("PreUpdate Check","ORDER","Add","")
	i udf["Y",err q err

	;adjust unit cost
	i '$g(PLIST(46)) s PLIST(46)=""
	;f jj=1:1:$g(PLIST) i $g(PLIST(jj))="" k PLIST(jj)
	s par=$g(par) 
	;n rowid,itemcat,calc,calcfl,phartype
	k PLIST(1),PLIST(2) s PLIST(0)=par
	;k PLIST(28),
	k PLIST(81),PLIST(84),PLIST(90),PLIST(76),PLIST(135)
	s calcfl=$$calcfl^DHCOEOrdItem($g(PLIST(4)))
	s phartype=$$phartype^DHCOEOrdItem($g(PLIST(4)))
	i calcfl["Y",phartype'["X" s:'$g(PLIST(85)) PLIST(85)=1 s PLIST(29)=$$CO29^at122($g(PLIST(85)),$g(PLIST(25)),$g(PLIST(35)),$g(PLIST(23)),$g(PLIST(17)),$g(PLIST(159))) ;k PLIST(29)
	i calcfl["Y",phartype["X" s PLIST(29)=$$CO29^at122(1,$g(PLIST(112)),$g(PLIST(113)),$g(PLIST(23)))
	i calcfl'["Y" s PLIST(29)=+$g(PLIST(29)) s:'PLIST(29) PLIST(29)=1
	s PLIST(76)=$$DEF76^DHCOEOrdItem($g(PLIST(0)),$g(PLIST(4)))
	s:PLIST(76)="Ignore" PLIST(76)="I"
	s:PLIST(76)="To Bill" PLIST(76)="TB"
	s CFEntryOrdBillPad=##class(web.PilotProject.DHCDocPPGroupSeting).GetConfigNode("EntryOrdBillPad")
	if ($g(PLIST("DHC",12))'="")&&(CFEntryOrdBillPad="1"){
		s tmpAdm=$p(^OEORD(par),"^",1)
		s AdmType=$p(^PAADM(tmpAdm),"^",2)
		if AdmType'="I" {
			s PLIST(76)="P"
		}else{
			s PLIST(76)="B"
		}
	}
	;if discontinued order then ignore 
	i $p($g(^OEC("OSTAT",+$g(PLIST(10)))),"^")="D" s PLIST(76)="I"
	i $p($g(^OEC("OSTAT",+$g(PLIST(10)))),"^")="DI" s PLIST(76)="I"
	;if executed  order then "TB"
	i $p($g(^OEC("OSTAT",+$g(PLIST(10)))),"^")="E" s PLIST(76)="TB"
	;if priority PRN then Ignore
	i $$admtype^DHCOEOrdItem(par)["I",$p($g(^OECPR(+$g(PLIST(23)))),"^")="PRN" s PLIST(76)="I"
	i $g(PLIST(111))="" s PLIST(111)="A"
	;if result status N, status should be executed
	i PLIST(111)="N" s PLIST(10)=$o(^OEC("OSTAT",0,"Code","E",""))
	;default value for field 54-insur billing conditions
	s:'$g(PLIST(54)) PLIST(54)=$$def1^DHCOEOrdItem(+$g(^OEORD(+par)),$g(PLIST(4)),$g(PLIST(17)))
	;i $d(PLIST) ;m ^zleon=PLIST
	;get default operation category
	s PLIST(64)=$$opercat^DHCOEOrdItem($g(PLIST(4)))
	i '$g(PLIST(161)) s PLIST(161)=$$admloc^DHCOEOrdItem(par)
	;clear user_read and assistant_dr fields
	;s PLIST(153)=""
	;s PLIST(157)=""
	;
	d pre
	;
	; piece 77 is the sequence number, sometimes in the vb stuff
	; this gets set to a string value e.g. 08 which then fails
	; validation. This next line ensures this doesn't happen.
	;s PLIST(77)=+$g(PLIST(77))
	i $g(PLIST(77))="" s PLIST(77)=0,err=$$seq^DHCOEOrdItem($g(PLIST(120)),"Cache")
	;fix some number fields
	;
	; they sometimes put in some strange data into these fields
	; so they should be converted to numeric, but only if they
	; exist otherwise it always puts a zero in the database for
	; every order which is wrong
	i $g(PLIST(59))'="" s PLIST(59)=+PLIST(59)
	i $g(PLIST(74))'="" s PLIST(74)=+PLIST(74)
	
	;获取病人当前出院状态,调用护理组接口
 	s CurrentDischargeStatus=##class(web.DHCDischargeHistory).GetCurrentDischargeStatus($p(^OEORD(par),"^",1))
 	;获取出院日期和时间
 	s DischargeDate="",DischargeTime=""
 	i CurrentDischargeStatus="B" {
		s DischargeDateTime=##class(web.DHCDischargeHistory).GetDischargeDateTime($p(^OEORD(par),"^",1))
		s DischargeDate=$p(DischargeDateTime,"^",1)
		i DischargeDate'="" Set PLIST(17)=DischargeDate
		s DischargeTime=$p(DischargeDateTime,"^",2)
		i DischargeTime'="" Set PLIST(18)=DischargeTime   	      
 	}
	
	
	
	k PLISTExt
	m PLISTExt=PLIST("DHC")
	KILL PLIST("DHC")
	;
	;s $ZT="ERROR^SSERR"
	s $ZT="ERROR"
	s rowid=""
	TS
	&sql( INSERT INTO SQLUser.OE_OrdItem VALUES :PLIST())
	s SQLflag=SQLCODE
	i 'SQLflag {
		s rowid=$p(%ROWID,$c(1))
		&sql(UPDATE SQLUser.OE_OrdItemExt VALUES :PLISTExt() WHERE OEORI_RowId=:rowid)
		if (SQLCODE'=0){
			///部分项目反映子表插入失败
			s count=$o(^DHCSYSERROR($ZN,+$h,""),-1)+1
			s ^DHCSYSERROR($ZN,+$h, count)="100^<ERROR>"_rowid_"---"_$ZERROR_"  "_$H_" "_$G(%msg)
			m ^DHCSYSERROR($ZN,+$h, count,"PLISTExt")=PLISTExt
		}
	}
	TC
	;B ;1111
	;m ^tmpPLIST(%ROWID)=PLIST
	;m ^tmpPLISTExt(%ROWID)=PLISTExt
	
	; Now retrieve everything back to return to client
	; %ROWID is returned from INSERT
	
	i 'SQLflag { 
		 d GenExe^DHCOEOrdExec(rowid)

 		if ##class(appcom.OEOrdItem).ISLongOrderPrior(+$g(PLIST(23))) {
	 		s ItmID=$P($G(^OEORD(+rowid,"I",$p(rowid,"||",2),1)),"^",2)
	 		s ItemCatDR=$p(^ARCIM(+ItmID,$p(ItmID,"||",2),1),"^",10)
    		s OrderType=$P(^ARC("IC",ItemCatDR),"^",7)
			//生成药品的关联执行记录,是否生成非药品的,根据设置"非药品生成第二天执行记录"
			s NonDrugCreatNextDayExec=$$getconfignode^DHCDocConfig("NonDrugCreatNextDayExec")
	 		if ((OrderType="R")||(NonDrugCreatNextDayExec=1)) d GenExe^DHCOEOrdExec(rowid,+$H+1)
	 	}
	}
	b ;insert over
	Quit SQLflag_"^"_rowid
ERROR 
	S VALUE=$ZE
	;
	TROLLBACK
	;
	s myDate=+$h
	s count=$o(^DHCSYSERROR($ZN,myDate,""),-1)+1

	s ^DHCSYSERROR($ZN,myDate, count)="100^<ERROR>"_VALUE_"---"_$ZERROR_"  "_$H
	; Force the error to show in VB still
	q "100^<ERROR>"_VALUE
pre ;
	;将字符串转换为List类型
	f ind=42,53 d
	.k TEMP
	.S CNT=$L($g(PLIST(ind)),"|")
	.F J=1:1:CNT S $LIST(TEMP,J)=$P($g(PLIST(ind)),"|",J)
	.S PLIST(ind)=TEMP
	.;F J=1:1:CNT S TEMP(J)=$P($g(PLIST(ind)),"|",J)
	.;K PLIST(ind) M PLIST(ind)=TEMP S PLIST(ind)=$O(PLIST(ind,""),-1)
	q
}

/// Creator:      周志强
/// CreatDate:    2012.05.31
/// Description:  根据传入的医嘱指针串产生合并标本号,用于护士重新并管用
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItemList:医嘱指针串,以”^"分割
/// Return: 
/// OutPut:		  医嘱指针!标本号
/// Others:       w ##class(appcom.OEOrdItem).GenLabEpisodeNo() 
ClassMethod GenLabEpisodeNo(OrdItemList As %String) As %String
{
	s ret=""
	s count=0
	Set rset=##class(%ResultSet).%New("web.DHCLISEpisode:GenerateEpisode")
	do rset.Execute(OrdItemList,"L")
	Set columns = rset.GetColumnCount()
	While (rset.Next()) {
		s OrdItemId=rset.GetDataByName("OrdItemId")
		s Flag=rset.GetDataByName("Flag")
		s LabEpisodeNo=rset.GetDataByName("EpisodeNo")
		continue:Flag'=0
		s obj=##class(User.OEOrdItem).%OpenId(OrdItemId)
		if $IsObject(obj) {
			s obj.OEORILabEpisodeNo=LabEpisodeNo
			d obj.%Save()
			d obj.%Close()
			s obj=""
			s count=count+1
			s single=OrdItemId_"!"_LabEpisodeNo
			if count=1 s ret=single
			e  s ret=ret_"^"_single
		}
	}
	d rset.Close()

	Q ret
}

/// Creator:      周志强
/// CreatDate:    2012.11.26
/// Description:  用于将门诊医嘱的执行记录,按医嘱计费模式转为按住院执行计费的模式,便于住院计入门诊发生的费用
/// 				  只处理医嘱相关第一条的执行记录和配药记录
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱表指针
/// Return: 
/// OutPut:		  0:成功 100:失败
/// Others:       w ##class(appcom.OEOrdItem).MigrateOPExec("88||5") 
ClassMethod MigrateOPExec(OrdItmRowId As %String) As %String
{
	s child=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",0))
	if child="" {
		s Date=$p(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),1),"^",9)
		s Time=$p(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),1),"^",10)
		s:'Time Time=$p($h,",",2)
		s ExecQty=+$p(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),1),"^",12) ;OEORI_PhQtyOrd
		s AdminQty=$$calcbillqty^DHCOEOrdExec(OrdItmRowId)
		;因为调用的住院产生执行记录的方法会自动插入执行和配药记录,但门诊可能已经插入过配药记录,
		;所以此处需要将门诊产生的发药记录数量置为0
		s ret=0
		TS
		s DSPRowId=0 for  {
			s DSPRowId=$O(^DHCOEDISQTY(0,"OEORI",OrdItmRowId,DSPRowId))
			Q:DSPRowId=""
		
			&SQL(Update SQLUser.DHC_OEDispensing Set DSP_TotalQty=0,DSP_Qty=0,DSP_ConfirmQty=0 Where DSP_RowId=:DSPRowId)
			if SQLCODE'=0 {
				Set ret=1
				Quit
			}
		}
		i ret=0 s ret=$$InsOEORE^DHCOEOrdExec(OrdItmRowId,Date,Time,ExecQty,"",AdminQty,1)
		i ret {
			TRO
		}else{
			TC
		}
		Q ret
	}
	s OEORERowId=OrdItmRowId_"||"_child
	
	s AdminQty=$$getAdminQty^DHCOEOrdExec(OrdItmRowId)
	;2017-03-06 Lid 获取部分退费数量
	s RefundQty=##class(web.UDHCJFBILL).GetApplyRefundQty(OrdItmRowId,"")
	s AdminQty=AdminQty-RefundQty ;
	
	
	s BillType=$p(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),11),"^",18)
	s Billed=$p(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),3),"^",5)
	s ItemStatus=$p(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),1),"^",13)
	TS
	&SQL(Update SQLUser.OE_OrdExec Set 
				OEORE_Billed=:Billed,
				OEORE_QtyAdmin=:AdminQty 
		Where OEORE_RowId=:OEORERowId)
	if SQLCODE'=0 {
		Tro
		Quit 100
	}
	&SQL(Update SQLUser.OE_OrdExecExt 
			Set OEORE_OrderStatus_DR=:ItemStatus,
				OEORE_BillType=:BillType				
		Where OEORE_RowId=:OEORERowId)
	if SQLCODE'=0 {
		Tro
		Quit 100
	}
	
	s err=0
	;如果有多条执行记录,则将除第一条以外的都将执行数量更新成0
	s childAfter=child
	for {
		s childAfter=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",childAfter)) q:childAfter=""
		s OEOREAfterRowId=OrdItmRowId_"||"_childAfter
		&SQL(Update SQLUser.OE_OrdExec Set 
				OEORE_Billed=:Billed,
				OEORE_QtyAdmin=0
		Where OEORE_RowId=:OEOREAfterRowId)
		if SQLCODE'=0 {
			Set err=1
			Quit
		}
	}
	if err=1 Tro  Quit 100
	s DSPRowId=0 for  {
		s DSPRowId=$O(^DHCOEDISQTY(0,"OEORI",OrdItmRowId,DSPRowId))
		Q:DSPRowId=""
		
		&SQL(Update SQLUser.DHC_OEDispensing Set DSP_OEORE_DR=:OEORERowId Where DSP_RowId=:DSPRowId)
		if SQLCODE'=0 {
			Set err=1
			Quit
		}
	}
	if err=1 Tro  Quit 100
	
	TC
	Q 0
}

/// 退材料库存调用材料组接口(住院按执行,门诊按医嘱)
ClassMethod ReturnMaterial(oeid As %String, NameSp As %String = "") As %String
{
	s $zt="ReturnMaterialErr"
	s MaterialBarCode=$p($G(^OEORD(+oeid,"I",$p(oeid,"||",2),"DHC")),"^",14)
	Q ##class(web.DHCSTM.PCHCOLLSM).Return(oeid,MaterialBarCode)
ReturnMaterialErr
	i $g(NameSp)'="" zn NameSp
	Q "-1"
}

/// 减材料库存调用材料组接口(住院按执行,门诊按医嘱)
/// 门诊会在medsrc下调用,所以使用第二个参数传入调用时的命名空间,以防报错不能正常切回原命名空间下
ClassMethod DispMaterial(oeid As %String, NameSp As %String = "") As %String
{
	s $zt="DispMaterialErr"
	s MaterialBarCode=$p($G(^OEORD(+oeid,"I",$p(oeid,"||",2),"DHC")),"^",14)
	Q ##class(web.DHCSTM.PCHCOLLSM).Disp(oeid,MaterialBarCode,"ORDER")
DispMaterialErr
	i $g(NameSp)'="" zn NameSp
	Q "-1"
}

// ##class(web.DHCDischargeHistory).CancelDoctorDischarge(episodId)

ClassMethod CancelDoctorDischarge(OrdItmRowId As %String, UserRowId As %String) As %String
{
	s err=0
	q:(OrdItmRowId="")||(UserRowId="") err
	s adm=$p(^OEORD(+OrdItmRowId),"^",1)
	;判断是否是将当前就诊置出院状态的出院医嘱
	s DischgOrderId=$p($g(^PAADM(adm,"DHC")),"^",28)
	q:DischgOrderId'=OrdItmRowId err
	s dischargeNeedArcimStr=##class(web.DHCDischargeHistory).GetDischargeNeedArcim("dischargeNeedArcim")
	s deathDischargeNeedArcimStr=##class(web.DHCDischargeHistory).GetDischargeNeedArcim("deathDischargeNeedArcim")
	s CheckArcimStr=""
	i dischargeNeedArcimStr'="" s CheckArcimStr=dischargeNeedArcimStr
	i deathDischargeNeedArcimStr'="" s CheckArcimStr=CheckArcimStr_"^"_deathDischargeNeedArcimStr
	s ArcimRowId1=$p($G(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),1)),"^",2)
	if ("^"_CheckArcimStr_"^")[("^"_ArcimRowId1_"^") d
	.s err=##class(web.DHCDischargeHistory).CancelDoctorDischarge(adm,UserRowId)
	q err
}

ClassMethod CheckOrdIsDis(OrdList As %String) As %String
{
	s dischargeNeedArcimStr=##class(web.DHCDischargeHistory).GetDischargeNeedArcim("dischargeNeedArcim")
	s deathDischargeNeedArcimStr=##class(web.DHCDischargeHistory).GetDischargeNeedArcim("deathDischargeNeedArcim")
	s NeedCheckArcimStr=""
	i dischargeNeedArcimStr'="" s NeedCheckArcimStr=dischargeNeedArcimStr
	i deathDischargeNeedArcimStr'="" s NeedCheckArcimStr=NeedCheckArcimStr_"^"_deathDischargeNeedArcimStr
	q:NeedCheckArcimStr="" 0
	s ret=0
    for i=1:1:$l(OrdList,"^") {
		set OrderItemStr=$p(OrdList,"^",i)
		set oeitm=$p(OrderItemStr,"!",1)
		if oeitm="" Continue
		s ArcimRowId=$p($G(^OEORD(+oeitm,"I",$P(oeitm,"||",2),1)),"^",2)
		i ("^"_NeedCheckArcimStr_"^")[("^"_ArcimRowId_"^") continue
		s ret=1
	}
	q ret
}

/// 停止或者作废医嘱的时候，判断是否需要刷新左侧的患者列表
/// retunr Y 刷新 N不刷新
ClassMethod RefresPatList(OrdList As %String) As %String
{
	s RefresArcimStr="12110||1"
	s ret="N"
    for i=1:1:$l(OrdList,"^") {
		set OrderItemStr=$p(OrdList,"^",i)
		set oeitm=$p(OrderItemStr,"!",1)
		if oeitm="" Continue
		s ArcimRowId=$p($G(^OEORD(+oeitm,"I",$P(oeitm,"||",2),1)),"^",2)
		i ("^"_RefresArcimStr_"^")'[("^"_ArcimRowId_"^") continue
		s ret="Y"
	}
	q ret
}

/// Description:TypeCode为空时为实习医师停止、作废、撤销医嘱；TypeCode为1时为上级医师审核
/// 
ClassMethod UpdateExtIfPractice(oeitm, UserRowID, StatusRowId As %String, ExpectEndDate As %String = "", TypeCode As %String = "")
{
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	if TypeCode="1"{
		&SQL(Update SQLUser.OE_OrdItemExt set OEORI_PracticeConfirmStopDate=:CurrDate,OEORI_PracticeConfirmStopTime=:CurrTime,OEORI_PracticeConfirmStopUser_DR=:UserRowID where OEORI_rowid=:oeitm)	
		Q SQLCODE
	}
	
	if UserRowID="" s UserRowID=$p($g(^OEORD(+oeitm,"I",+$p(oeitm,"||",2),7)),"^",1)
	&SQL(Select SSUSR_CareProv_DR into :DoctorRowId from SQLUser.SS_User where SSUSR_RowId=:UserRowID )
	if DoctorRowId'=""{
		s practice=##class(web.DHCOEOrdItem).practice(DoctorRowId)
		
		if practice=1{
			if ($g(ExpectEndDate)'="")&&(ExpectEndDate>CurrDate){
				Q "-401"		
			}
			&SQL(Update SQLUser.OE_OrdItemExt set OEORI_PracticeConfirmStopStatus=:StatusRowId,OEORI_PracticeStopUser_DR=:UserRowID where OEORI_rowid=:oeitm)
			if SQLCODE  Q "-400"
			else  Q "PS"
		}	
	}
	Q 0
}

/// Creator:      宋春莉
/// CreatDate:    2018.10.26
/// Description:  撤销预停
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针,PWFlag:是否密码验证,PinNum:明文密码
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).StopMulti("531546||1",590,"") 
ClassMethod CancelPreStopMulti(OrdList As %String = "", UserID As %String = "", PinNum As %String, ExpStr As %String, PWFlag As %String = "Y")
{
	s ^TEMP("Debug","CancelPreStopMulti")="w ##class(appcom.OEOrdItem).CancelPreStopMulti("""_OrdList_""","""_UserID_""","""_PinNum_""","""_PWFlag_""")"
	s user=$p(ExpStr,"^",1)
	s locid=$p(ExpStr,"^",2)
	s groupid=$p(ExpStr,"^",3)
	;密码验证
	s err=0
 	if PWFlag="Y" s err=##Class(web.DHCOEOrdItem).PinNumberValid(UserID,PinNum)
	Q:err'=0 err
 	;重新组织停医嘱串,根据配置停主医嘱
 	s StopGroupOrder=##Class(web.DHCDocConfig).GetConfigNode("StopGroupOrder")
 	s OrdListStr=""
 	s Len=$l(OrdList,"^")
 	for i=1:1:Len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)    //不能改医嘱ID为第一位的位置
		;不必从界面取的关联医嘱RowId   zhouzq 2010.07.21
		s OrdLinkRowId=$p($g(^OEORD(+oeitm,"I",$p(oeitm,"||",2),11)),"^",39)
		;add by zhouzq 2012.06.08
		s SingleStopFlag=..CheckSingleStop(oeitm,UserID)
		if SingleStopFlag'=1 {
			if (StopGroupOrder=1){
				;如果确认成组停止,子医嘱RowId不需要传了
				if (OrdLinkRowId'="") {
					s flag = ##class(web.DHCDocMain).CheckStopOrder(OrdLinkRowId,user,locid,groupid,"","")
					if (+flag'=1){
						continue
					}
					if (OrdListStr'[(OrdLinkRowId_"!")){
						 s OrderItemStr=OrdLinkRowId
					}else{
						continue
					}
				}else{
					if (OrdListStr[(oeitm_"!")){
						continue
					}
				}
			}else{
				;如果已经选择了子医嘱,子医嘱RowId不需要传了
				if (OrdLinkRowId'="")&&(OrdListStr[(OrdLinkRowId_"!")) continue
			}
		}
		if OrdListStr="" s OrdListStr=OrderItemStr
		else  s OrdListStr=OrdListStr_"^"_OrderItemStr
	}
	s adm=""
 	s err=0
 	s OrdList=OrdListStr
 	s len=$l(OrdList,"^")
	for i=1:1:len {
		s OrderItemStr=$p(OrdList,"^",i)
		s oeitm=$p(OrderItemStr,"!",1)
		s err=..CancelPreStop(oeitm,UserID)
		s adm=$p(^OEORD(+oeitm),"^",1)
	 }
	 Q:err'=0 err
	 q err
}

/// Creator:      宋春莉
/// CreatDate:    2018.10.26
/// Description:  撤销预停 修改预停时间为空
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 	  0:成功
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdItem).CancelPreStop("77078||44",127) 
ClassMethod CancelPreStop(OrdItmRowId As %String, UserRowId As %String) As %String
{
	set obj=##class(User.OEOrdItem).%OpenId(OrdItmRowId)
	if '$IsObject(obj) Quit "-100"			   //医嘱不存在
	s err=0
	TS
	&SQL(Update SQLUser.OE_OrdItem Set OEORI_EndDate=null,OEORI_EndTime=null,OEORI_UserUpdate=:UserRowId where OEORI_Rowid=:OrdItmRowId)
	if SQLCODE Tro  Q SQLCODE
	s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,0))
	While (Sub'="") {
		s SubRowId=+OrdItmRowId_"||"_Sub
		;已经停止的医嘱不用再处理
		s SubStatusCode=..GetStatusCode(SubRowId) 
		if (SubStatusCode="D")||(SubStatusCode="C")||(SubStatusCode="U") {
			s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
			continue
		}
    	&SQL(Update SQLUser.OE_OrdItem Set OEORI_EndDate=null,OEORI_EndTime=null,OEORI_UserUpdate=:UserRowId where OEORI_Rowid=:SubRowId)
    	if SQLCODE {
			s err="-202"      //更新预停时间
			Quit
		}
		s Sub=$O(^OEORDi(0,"OEORI",+OrdItmRowId,OrdItmRowId,Sub))
	}
	i err TRo  Q err
	TC
	Quit 0
}

ClassMethod CancelOrdDocInterface(OrdItmRowId As %String, UserRowId As %String) As %String
{
	s Adm=$P(^OEORD(+OrdItmRowId),"^",1)
	s PAADMType=$p($g(^PAADM(Adm)),"^",2)
	if (PAADMType="I"){
		//撤销医疗结算
		s err=..CancelDoctorDischarge(OrdItmRowId,UserRowId)
		if +err'=0 Q err
	}
	;自动撤消治疗申请单
	s err=##class(DHCDoc.DHCDocCure.Apply).CancelCureApplyByStopOrd(OrdItmRowId,UserRowId)
	if +err'=0 Q err
	;自动撤销会诊申请
	s err=##Class(web.DHCEMConsInterface).CanCstNo(UserRowId,OrdItmRowId)
	i +err=100 s err=0
	if +err'=0 Q err
	
	;自动撤销手术申请
	s err=##class(web.DHCANAdaptor).CancelOperByOeordId(OrdItmRowId)
	i +err=100 s err=0
	if +err'=0 Q $P(err,"^",2)
	;;药房追踪接口
	if $d(^PHAPRESTRACKi("MOEORI",OrdItmRowId)) {
		s TrackLoc=$p($g(^OEORD(+OrdItmRowId,"I",$p(OrdItmRowId,"||",2),7)),"^",2)
		d ##class(web.DHCINPHA.HMPresTrack.SqlDbPresTrack).HandlePresTrackDB(OrdItmRowId_"^"_""_"^"_""_"^"_"A2"_"^"_TrackLoc_"^"_UserRowId)
	}
	q 0
}

ClassMethod GetCstRelOeori(OrdList As %String) As %String
{
	s Ord=+OrdList
	s EpisodeID=$P(^OEORD(Ord),"^",1)
	s AdmType=$p(^PAADM(EpisodeID),"^",2)
	if (AdmType="I"){
		s Seq="!"
	}else{
		s Seq="&"
	}
	s OrdListStr=""
	s len=$l(OrdList,"^")
	for i=1:1:len {
		s TotString=$p(OrdList,"^",i)
		s oeitm=$p(TotString,Seq,1)
		//多科会诊申请产生的其他申请医嘱串
		s CstRelOeoriStr=##Class(web.DHCEMConsInterface).GetCstRelOeori(oeitm)
		continue:CstRelOeoriStr=""
		for j=1:1:$l(CstRelOeoriStr,"^"){
			s oneCstRelOeori=$p(CstRelOeoriStr,"^",j)
			if ("^"_OrdList_"^")'[("^"_oneCstRelOeori_"^"){
				if (OrdListStr="") s OrdListStr=oneCstRelOeori
				else  s OrdListStr=OrdListStr_"^"_oneCstRelOeori
			}
		}
	}
	q OrdListStr
}

}
