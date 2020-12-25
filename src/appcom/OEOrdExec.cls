/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  用于执行记录处理的公共服务类
/// 错误代码说明
/// -303:执行记录状态没有变化, 不用改变
/// -304:执行记录已经执行,不能停止
/// -302:执行记录已经停止,不能再执行
/// -305:执行记录没有执行,不需要撤销
/// -306:执行记录保存失败
/// -307:执行记录变化表保存失败
/// -308:执行记录计费变化表保存失败
/// -310:执行记录扩展表保存失败
/// -301:停止医嘱执行记录失败
/// -310:计费状态相同,不用改变
/// -311:已经退费,不需要再免费
/// -313:已经待计费,不需要取消免费
/// -314:临时医嘱未停止或者撤销,不能停止执行
/// -315:修改执行记录医嘱状态失败
/// -316:已作废或撤销的临时医嘱的执行记录,不允许执行
/// -317:长期医嘱停止时间后的执行记录不允许再执行
/// -318:已经发药不允许停止执行(仅限门急诊)
Class appcom.OEOrdExec Extends %RegisteredObject [ ClassType = "", ProcedureBlock ]
{

/// 得到默认的费别
ClassMethod GetDefaultBillType(OEORIRowId) As %String
{
	s EpisodeID=$P(^OEORD(+OEORIRowId),"^",1)
	Q:EpisodeID="" ""
	s AdmBillType=$p($g(^PAADM(EpisodeID,1)),"^",7)
	Q AdmBillType
}

/// 插入执行记录	
ClassMethod InsExecOEORE(OEORIRowId As %String, exDate As %String, Time, LinkOEORE As %String = "")
{
 s oeori = +OEORIRowId
 s suboeori = $p(OEORIRowId,"||",2)
 s ARCIMrow	= $p(^OEORD(oeori,"I",suboeori,1),"^",2)
 s drgform=$p($g(^ARCIM(+ARCIMrow,+$p(ARCIMrow,"||",2),1)),"^",12)
 s arcgrp=$p(^ARCIM(+ARCIMrow,$p(ARCIMrow,"||",2),1),"^",10)
 s cattype=$p(^ARC("IC",arcgrp),"^",7)
 s uom=$p($g(^OEORD(oeori,"I",suboeori,2)),"^",3)
 s Dose=$p($g(^OEORD(oeori,"I",suboeori,2)),"^",1) s:'Dose Dose=1 ;Dose Qty 
 s ExecQty = Dose
 s PackQty=$p($g(^OEORD(oeori,"I",suboeori,9)),"^",4)
 s baseuom=$$baseuom^DHCDocOrderCommonNew(ARCIMrow)
 i cattype="R"{
	i PackQty="" {
		s AdminQty=$$calcqty^DHCOEOrdItem(drgform,uom,ExecQty)
	}else{
		s convFac=##class(appcom.OEDispensing).convFac(ARCIMrow)
		s AdminQty=PackQty*convFac
	}
 }else{
	s AdminQty=ExecQty 
 }
 
 ;s LinkOEORIRowId=$p(^OEORD(oeori,"I",suboeori,11),"^",39)
 ;s billtype=..GetDefaultBillType(OEORIRowId)
 s hdate = ##class(websys.Conversions).DateHtmlToLogical(exDate) //$zdh(exDate,1)
 s count=1
 s time=0 f  s time= $o(^OEORDi(0,"Date",oeori,hdate,time)) q:time=""  d
 .s child = 0 f  s child=$o(^OEORDi(0,"Date",oeori,hdate,time,suboeori,child))  q:child=""  d
 ..s count=count+1
 if LinkOEORE="" {
 	d ..InsOEORE(OEORIRowId,hdate,$zth(Time),ExecQty,0,AdminQty,count,"","")
 	s child=$O(^OEORDi(0,"OrdItem",+OEORIRowId,$p(OEORIRowId,"||",2),hdate,""),-1)
	if child'="" s LinkOEORE=OEORIRowId_"||"_child
 	s child=0  F {
		s child=$O(^OEORDi(0,"OEORI",+OEORIRowId,OEORIRowId,child))
		Q:child=""
		s SubRowId=+OEORIRowId_"||"_child
		s itemStatDr = $p(^OEORD(+OEORIRowId,"I",child,1),"^",13) 		;OEORI_ItemStat_DR ;OEC_OrderStatus
		s:+itemStatDr>0 TItemStatCode = $p(^OEC("OSTAT",itemStatDr),"^",1) 
		d ..InsExecOEORE(SubRowId,exDate,Time,LinkOEORE)
	}
 }else{
	d ..InsOEORE(OEORIRowId,hdate,$zth(Time),ExecQty,0,AdminQty,count,LinkOEORE,"")
 }
 q 0
}

ClassMethod InsOEORE(OEORIRowId, Date, Time, ExecQty, QtyOver, AdminQty, SeqNo, LinkOEORE, XTime)
{
	q $$InsOEORE^DHCOEOrdExec(OEORIRowId,Date,Time,ExecQty,QtyOver,AdminQty,SeqNo,LinkOEORE,XTime)
	q 0
}

/// Creator: 		周志强
/// CreatDate: 		2012-03-08
/// Description: 	更新执行状态
/// Table：			OE_OrdExec
/// Input：			oeoreId:医嘱执行表ID,NewStatusCode:状态代码,ChangeReasonRowId:改变原因,UserRowId:用户指针
/// Return：		0:成功返回 其他:错误代码
/// Other           w ##class(appcom.OEOrdExec).UpdateStatus("77073||1||2","C",127,+$H,"","")
ClassMethod UpdateStatus(OEORERowId As %String, NewStatusCode As %String, UserRowId As %String, ExeDate As %Date = "", ExeTime As %Time = "", ChangeReasonRowId As %String = "", StopAllExecFlag As %String = "", Reasoncomment As %String = "", ExecCTLocDr As %String = "", IsBillN As %String = "Y") As %String
{
	s ^tempscl("UpdateStatus")=OEORERowId_","_NewStatusCode_","_UserRowId_","_ExeDate_","_ExeTime_","_ChangeReasonRowId_","_StopAllExecFlag_","_Reasoncomment_","_ExecCTLocDr_","_IsBillN
	s OldStatusCode=""
	s OldStatusRowId=$P(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3)),"^",16)
	if OldStatusRowId'="" s OldStatusCode=$P($G(^OEC("STAT",OldStatusRowId)),"^",1)
 	
 	if OldStatusCode=NewStatusCode Quit "-303"
	s BillStatus=$P(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3)),"^",6)
	
	s EpisodeID=$p(^OEORD(+OEORERowId),"^",1)
	s EpisodeType=$p(^PAADM(EpisodeID),"^",2)
	s ChangeBillStatus=""

  	;如果需停止的执行记录未账单并且已经发药,先做账单退费,以避免漏费
	if (EpisodeID'=""),BillStatus'="B",##class(appcom.OEDispensing).Collected(OEORERowId) {
		s Conf=$O(^DHCTarC("CF",""))
		s TotalBillFalg=$s(Conf'="":$p(^DHCTarC("CF",Conf),"^",5),1:"")
		s MotherEpisodeID=$P($g(^PAADM(EpisodeID)),"^",75)
		//如果计费设置的是包含新生儿费用,调用账单程序时需要传入母亲的就诊指针 2013.3.12 zhouzq
		if (TotalBillFalg="Y") && (MotherEpisodeID'="") {
			d ##Class(web.UDHCJFBILL).BILLN(MotherEpisodeID,UserRowId,"")
		}else{
			d ##Class(web.UDHCJFBILL).BILLN(EpisodeID,UserRowId,"")
		}
		s BillStatus=$P(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3)),"^",6)
	}
	s CureAppFlag="",CureAARowId=""
 	if NewStatusCode="D" {
	 	s PriorityDR=$p($g(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),1)),"^",8)
	 	s ExeOrderStatusId=$P($g(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3),"BILL")),"^",1)
		s ExeStatusCode=$S(ExeOrderStatusId'="":$P($G(^OEC("OSTAT",ExeOrderStatusId)),"^",1),1:"")
		;治疗记录已经预约,不能停止执行  2016-05-13
		;s AppFlag=##class(DHCDoc.DHCDocCure.Appointment).GetExecResultAppStatus(OEORERowId)
		;if (AppFlag=1) Q "-314"
		;2018-06-28 nk-update 
		;已经治疗的治疗记录不允许停止,下方事务中添加取消治疗预约'AppCancelHUI'方法调用
		s AppFlag=##class(DHCDoc.DHCDocCure.Appointment).GetExecCureAppStatus(OEORERowId)
		if AppFlag'=""{
			s CureAARowId=$p(AppFlag,"^",2)
			s CureAppFlag=$p(AppFlag,"^",1)
			if (AppFlag="A"){
				Q "-401"
			}
		}
		s DCARowID=$o(^DHCDocCure(0,"OEORI",+OEORERowId_"||"_$P(OEORERowId,"||",2),""))
		//2016-06-15如果是治疗项目则不判断医嘱的状态
		if ##class(appcom.OEOrdItem).ISShortOrderPrior(PriorityDR),ExeStatusCode'="C",ExeStatusCode'="D",DCARowID="" Q "-314"
		if EpisodeType'="I",##class(appcom.OEDispensing).Collected(OEORERowId) Q "-318"
		if (OldStatusCode="F")&&(StopAllExecFlag'=1) Quit "-304"
		if ##class(appcom.OEOrdItem).IsHourOrderItem(OEORERowId) {
			s Conf=$O(^DHCTarC("CF",""))
			s TotalBillFalg=$s(Conf'="":$p(^DHCTarC("CF",Conf),"^",5),1:"")
			s MotherEpisodeID=$P($g(^PAADM(EpisodeID)),"^",75)
			//如果计费设置的是包含新生儿费用,调用账单程序时需要传入母亲的就诊指针 2013.3.12 zhouzq
			if (TotalBillFalg="Y") && (MotherEpisodeID'="") {
				d ##Class(web.UDHCJFBILL).BILLN(MotherEpisodeID,UserRowId,"")
			}else{
				d ##Class(web.UDHCJFBILL).BILLN(EpisodeID,UserRowId,"")
			}
			s BillStatus=$P(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3)),"^",6)
			if " B TB "[(" "_BillStatus_" ") s ChangeBillStatus="I"
		}else{
			if BillStatus="B" s ChangeBillStatus="I"
			if BillStatus="TB" s ChangeBillStatus="R"
		}
	}
			
 	if NewStatusCode="F" {
	 	if OldStatusCode="D" Q "-302"
	 	s OrderStatusCode=""
	 	s PriorityDR=$p($g(^OEORD(+OEORERowId,"I",+$p(OEORERowId,"||",2),1)),"^",8)
		s OrderStatusRowId=$P($g(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3),"BILL")),"^",1)
		s OrderStatusCode=$S(OrderStatusRowId'="":$P(^OEC("OSTAT",OrderStatusRowId),"^",1),1:"")
		if ##class(appcom.OEOrdItem).ISShortOrderPrior(PriorityDR) {
 			if OrderStatusCode="D" Q "-316"
 			if OrderStatusCode="C" Q "-316"
 			if OrderStatusCode="U" Q "-316"		
		}else{
 			if OrderStatusCode="D" Q "-317"
 			if OrderStatusCode="C" Q "-317"
 			if OrderStatusCode="U" Q "-317"		
		}
		;if BillStatus="B" s ChangeBillStatus="TB"
		;药品未审核,不能执行
		;非皮试的药品医嘱判断药房是否审核
		s skintest=$p($g(^OEORD(+OEORERowId,"I",+$p(OEORERowId,"||",2),5)),"^",2)
		s OrdPriorityDR=$p(^OEORD(+OEORERowId,"I",+$p(OEORERowId,"||",2),1),"^",8)
		s PriorCode=$p($g(^OECPR(OrdPriorityDR)),"^")
		if (skintest'="Y")&&(PriorCode'="OM")&&(PriorCode'="OMST")&&(PriorCode'="OMCQZT")&&(PriorCode'="OMLSZT"){
			Set IPMonitorResult=##class(web.DHCSTINTERFACE).GetOrdIPMonitorResult($p(OEORERowId,"||",1,2))
			if (IPMonitorResult="N"){
				Quit "-3177"
			}
		}
	}

 	if NewStatusCode="C" {
		if (OldStatusCode'="F") Quit "-305"
		;撤销执行时不改变计费状态
		;if BillStatus="B" s ChangeBillStatus="I"
		;if BillStatus="TB" s ChangeBillStatus="R"
	}
	
	s CPRowId=##class(web.SSUser).GetDefaultCareProvider(UserRowId)
	s NewStatusRowId=$O(^OEC("STAT",0,"Code",NewStatusCode,0))
	
	if ExeDate="" s ExeDate=+$H
	if ExeTime="" s ExeTime=$P($H,",",2)
	Ts
	if ((CureAppFlag="I")&&(CureAARowId'="")){
		;预约未治疗的取消预约并停止执行
		d ##class(DHCDoc.DHCDocCure.Appointment).AppCancelHUI(CureAARowId,UserRowId,"1")
	}
			
    s obj=##class(User.OEOrdExec).%OpenId(OEORERowId)
    if $ISObject(obj) {
	    d obj.OEOREOrderStatusDRSetObjectId(NewStatusRowId)
	    i (ChangeBillStatus'="") s obj.OEOREBilled=ChangeBillStatus
	    i (CPRowId'="") d obj.OEORECTPCPDRSetObjectId(CPRowId)
	    s obj.OEOREDateExecuted=ExeDate
	    s obj.OEORETimeExecuted=ExeTime
	    /*
	    if NewStatusCode="F" {
	
		    i (ExeDate'="") s obj.OEOREDateExecuted=ExeDate
		    i (ExeTime'="") s obj.OEORETimeExecuted=ExeTime
	    }
	    */
	    
	    if NewStatusCode="D" {
		    s obj.OEOREXDate=ExeDate
		    s obj.OEOREXTime=ExeTime
	    }
	    s ExpectDate=obj.OEOREExStDate
	    s sc=obj.%Save()
	    If $$$ISERR(sc) Tro  Quit "-306"
	    d obj.%Close()
	    s obj=""
	    
	    if NewStatusCode="D" {
		    s objext=##class(User.OEOrdExecExt).%OpenId(OEORERowId)
		    if $ISObject(objext) {
			    s DCOrderStatusRowId=$O(^OEC("OSTAT",0,"Code","D",0))
				if DCOrderStatusRowId'="" {
				    d objext.OEOREOrderStatusDRSetObjectId(DCOrderStatusRowId)
			    	s sc=objext.%Save()
			    	If $$$ISERR(sc) Tro  Quit "-306"
				}
				d objext.%Close()
			   	s objext=""
		    }
	    }
	    if (NewStatusCode="F"){
			s objext=##class(User.OEOrdExecExt).%OpenId(OEORERowId)
		    if $ISObject(objext) {
		    	if (ExecCTLocDr'=""){
			    	d objext.OEOREUserCTLOCDRSetObjectId(ExecCTLocDr)
			    	s WardRowID=$O(^PAWARD(0,"WARD_LocationDR",ExecCTLocDr,""))
			    	if (WardRowID'=""){
				    	d objext.OEOREUserWardDRSetObjectId(WardRowID)
				    }
			    }
		    	s sc=objext.%Save()
		    	If $$$ISERR(sc) Tro  Quit "-306"
				d objext.%Close()
		    }
		    s objext=""
		}
	    ;插入状态变化表
	   	s objstatus=##class(User.OEOrdExecStatus).%New(OEORERowId)
		d objstatus.STCHParRefSetObjectId(OEORERowId)
		d objstatus.STCHAdminStatusDRSetObjectId(NewStatusRowId)
		if ChangeReasonRowId'="" d objstatus.STCHReasonDRSetObjectId(ChangeReasonRowId)
		e  i Reasoncomment'="" s objstatus.STCHReasonComtent=Reasoncomment
		s objstatus.STCHDate=+$H
		s objstatus.STCHTime=$P($H,",",2)
		d objstatus.STCHUserDRSetObjectId(UserRowId)
		s sc=objstatus.%Save()
		If $$$ISERR(sc) Tro  Quit "-307"
	    d objstatus.%Close()
	    s objstatus=""
	    
	    ;集成平台接口,执行和停止执行时发送消息
	    if NewStatusCode="F" {
	    	;d ##class(web.DHCENS.EnsHISService).DHCHisInterface("SENDNURORDITEMINFO",OEORERowId)
	    }
	    if NewStatusCode="D" {
	    	;d ##class(web.DHCENS.EnsHISService).DHCHisInterface("SENDNURCANCELORDITEMINFO",OEORERowId)
	    }
	    ;处理关联的执行记录的状态
	    s OEORIRowId=$P(OEORERowId,"||",1,2)
	    s child=0  F {
			s child=$O(^OEORDi(0,"OEORI",+OEORIRowId,OEORIRowId,child))
			Q:child=""
			s childsub=0  F {
				s childsub=$O(^OEORDi(0,"OrdItem",+OEORIRowId,child,ExpectDate,childsub))
				Q:childsub=""
				s LinkOEORE=$P($G(^OEORD(+OEORIRowId,"I",child,"X",childsub,"BILL")),"^",3)
				s SubOEORE=+OEORIRowId_"||"_child_"||"_childsub
				if OEORERowId=LinkOEORE {
					d ..UpdateStatus(SubOEORE,NewStatusCode,UserRowId,ExeDate,ExeTime,ChangeReasonRowId,StopAllExecFlag,Reasoncomment,ExecCTLocDr,IsBillN)
					;加逻辑库存
					if '##class(appcom.OEDispensing).Collected(SubOEORE) {
						if (NewStatusCode="D") {
					    	d ##Class(appcom.OEDispensing).Return(SubOEORE)
				    	}
					}
				}
			}
		}
	    ;加逻辑库存
	    if '##class(appcom.OEDispensing).Collected(OEORERowId) {
			if (NewStatusCode="D") {
		    	d ##Class(appcom.OEDispensing).Return(OEORERowId)
	    	}
		}
    }
    Tc
    s LinkOEORIRowId=$p(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),11),"^",39)
	;产生退药单
	if NewStatusCode="D" d ##Class(web.DHCSTRETREQUEST).CreateDrugReqByXtime(OEORERowId,UserRowId)
	;if LinkOEORIRowId="" 
	d ##class(Nur.DHCInstrAttOrdByWard).ExcuteInstrAttOrdNew(OEORERowId,NewStatusCode,ExecCTLocDr,UserRowId)
	s EpisodeID=$p(^OEORD(+OEORERowId),"^",1)
	if EpisodeID'="",IsBillN'="N" {
		d ##Class(web.UDHCJFBILL).BILLN(EpisodeID,UserRowId,"")
		s MotherAdm=$p($g(^PAADM(EpisodeID)),"^",75)
		if MotherAdm'="" d ##Class(web.UDHCJFBILL).BILLN(MotherAdm,UserRowId,"")
	}
	///处方跟踪  bobo
	s FindCTLOCID=$p($g(^OEORD(+OEORERowId,"I",$p(OEORERowId,"||",2),7)),"^",2)
	s prescNo=$p($g(^OEORD(+OEORERowId,"I",+$p(OEORERowId,"||",2),1)),"^",14)   //处方号
	s FindOrdItem=$g(^OEORD("XJZY","FindS",+OEORERowId_"||"_+$p(OEORERowId,"||",2)))
	if $d(^PHAPRESTRACKi("MOEORI",+OEORERowId_"||"_+$p(OEORERowId,"||",2))) d
	.i (NewStatusCode="F") d ##class(web.DHCPHACOM.ComInterface.FaceOutToDHC).SavePresTrack("^"_OEORERowId_"^"_prescNo_"^B2^"_FindCTLOCID_"^"_UserRowId)
	.i (NewStatusCode="D") d ##class(web.DHCPHACOM.ComInterface.FaceOutToDHC).SavePresTrack("^"_OEORERowId_"^"_prescNo_"^B5^"_FindCTLOCID_"^"_UserRowId)
	.i (NewStatusCode="C") d ##class(web.DHCPHACOM.ComInterface.FaceOutToDHC).SavePresTrack("^"_OEORERowId_"^"_prescNo_"^B3^"_FindCTLOCID_"^"_UserRowId)

	q 0
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  将医嘱停止时间后的所有未执行记录变为"停止执行"状态
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱指针,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).DiscontinueExec("531546||1",590) 
ClassMethod DiscontinueByXTime(OrdItmRowId As %String, UserRowId As %String, StopAllExecFlag As %String = "", IsBillN As %String = "Y") As %String
{
	s err=0
	s XDate=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),3)),"^",34)
	s XTime=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),2)),"^",15)
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	if XTime="" s XTime=CurrTime
	
	s arcim=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),1)),"^",2)
	if arcim="" Q 0
	
	s AutoDCFlag=$g(^DHCDocConfig("StopExecByDCOrder"))
	if AutoDCFlag'=1 {
		s ItemCatRowId=+$p($g(^ARCIM(+$g(arcim),1,1)),"^",10)
		s UserDepartmentRowId=$p($g(^OEORD(+OrdItmRowId,"I",+$p(OrdItmRowId,"||",2),7)),"^",2)
		if UserDepartmentRowId'="" {
			s AutoDCFlag=$P($g(^CTLOC(UserDepartmentRowId,"DHC")),"^",8)
			if AutoDCFlag'=1 {
				if ItemCatRowId'="" {
					s AutoDCFlag=$$GetDHCARCItemCatFieldValue^DHCDocConfig(ItemCatRowId,4)
				}
			}
		}
	}
	s DCStatusRowId=$O(^OEC("STAT",0,"Code","D",0))
	s Sub=0  f {
		s Sub=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub))
		Q:Sub=""
		
		s ExeDate=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",1)
		s ExeTime=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",2)
		if CurrDate>ExeDate Continue
		
		;已经结算了,不能停止
		s BillStatus=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",6)
		if BillStatus="P" Continue  
		    
		s rowid=OrdItmRowId_"||"_Sub
		;处理小时医嘱的执行记录,置上停止时间
		if ##class(appcom.OEOrdItem).IsHourOrderItem(OrdItmRowId) {
			;小时医嘱停止提前到0点,退费会有问题;要求执行日期为当前日期则按当前时间停止,大于则停止到00:00:01
			if CurrDate'<ExeDate {
				if XTime=0 s XTime=1
			}else{
				s XTime=1
			}
			s err=##class(appcom.OEOrdExec).SetBillFlag(rowid,XTime)
		}
		
		s StatusRowId=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",16)
		s StatusCode=$s(StatusRowId'="":$P($G(^OEC("STAT",StatusRowId)),"^",1),1:"")
		if (StatusCode'="")&&(StatusCode'="A")&&(StatusCode'="C")&&(StopAllExecFlag'=1) Continue
		if CurrDate=ExeDate,XTime>ExeTime,StopAllExecFlag'=1 Continue
		
		s StatusRowId=$O(^OEC("OSTAT",0,"Code","D",0))
		
		&SQL(Update SQLUser.OE_OrdExecExt Set OEORE_OrderStatus_DR=:StatusRowId Where OEORE_RowId=:rowid)
		do ##class(User.OEOrdExecOrdStatus).Save(rowid_"^"_StatusRowId_"^"_UserRowId_"^^^^")
		
		if (AutoDCFlag=1) d ##class(appcom.OEOrdExec).UpdateStatus(rowid,"D",UserRowId,"","","",StopAllExecFlag,"","",IsBillN)

		s err=SQLCODE
		if err Quit
		;产生退药单
		;d ##class(web.DHCSTRETREQUEST).CreateDrugReqByXtime(rowid,UserRowId)

	}
	if err Quit "-301"
	Quit err
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  停止执行指定的执行记录
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).Discontinue("77071||46",127) 
ClassMethod Discontinue(OEORERowId As %String, UserRowId As %String) As %String
{
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  在医嘱撤销和作废时,将所有执行记录都停止执行
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针,StopFlag:是否停止执行记录
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).DiscontinueAll("531546||1",590) 
ClassMethod DiscontinueAll(OrdItmRowId As %String, UserRowId As %String, StopFlag As %String = "", IsBillN As %String = "Y", StopAllExecFlag As %String = "") As %String
{
	s err=0
	s CurrDate=$p($h,",",1)
	s CurrTime=$p($h,",",2)
	if (StopAllExecFlag'="1"){
		//已经执行的医嘱不能作废或者收费不能停止
		if ##class(appcom.OEOrdItem).Executed(OrdItmRowId) Quit "-302" 
	}
	
	s DCStatusRowId=$O(^OEC("STAT",0,"Code","D",0))
	s Sub=0  f {
		s Sub=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub))
		Q:Sub=""
		s ExeDate=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",1)
		s ExeTime=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",2)
		
		;已经结算了,不能作废
		s BillStatus=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",6)
		if BillStatus="P" Continue  
		
		s rowid=OrdItmRowId_"||"_Sub
		;处理小时医嘱的执行记录,置上停止时间(对于作废医嘱将时间置为开始时间,保证能全部账单退费)
		s XTime=ExeTime
		if ##class(appcom.OEOrdItem).IsHourOrderItem(OrdItmRowId) {
			;小时医嘱停止提前到0点,退费会有问题;要求执行日期为当前日期则按当前时间停止,大于则停止到00:00:01
			if CurrDate'<ExeDate {
				if XTime=0 s XTime=1
			}else{
				s XTime=1
			}
			s err=##class(appcom.OEOrdExec).SetBillFlag(rowid,XTime)
			
		}
		s StatusRowId=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",16)
		s StatusCode=""
		if StatusRowId'="" s StatusCode=$P($G(^OEC("STAT",StatusRowId)),"^",1)
		if (StatusCode'="")&&(StatusCode'="A")&&(StatusCode'="C")&&(StopAllExecFlag'="1") Continue
		
		s StatusRowId=$O(^OEC("OSTAT",0,"Code","D",0))
		&SQL(Update SQLUser.OE_OrdExecExt Set OEORE_OrderStatus_DR=:StatusRowId Where OEORE_RowId=:rowid)
		do ##class(User.OEOrdExecOrdStatus).Save(rowid_"^"_StatusRowId_"^"_UserRowId_"^^^^")
		
		if SQLCODE s err=SQLCODE Quit
		
		;临时医嘱作废或者撤销可以直接停止执行记录
		if StopFlag d ##class(appcom.OEOrdExec).UpdateStatus(rowid,"D",UserRowId,"","","",StopAllExecFlag,"","",IsBillN)
		
		/*
		s BillStatus=$P(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub),"^",6)
		s ChangeBillStatus=""
		if BillStatus="B" s ChangeBillStatus="I"
		if BillStatus="TB" s ChangeBillStatus="R"
		if ChangeBillStatus="" {
			&SQL(Update SQLUser.OE_OrdExec Set OEORE_Order_Status_DR=:DCStatusRowId Where OEORE_RowId=:rowid)
		}else{
			&SQL(Update SQLUser.OE_OrdExec Set OEORE_Order_Status_DR=:DCStatusRowId,OEORE_Billed=:ChangeBillStatus Where OEORE_RowId=:rowid)
		}
		if SQLCODE s err=SQLCODE Quit
		
		if '##class(appcom.OEDispensing).Collected(rowid) {
			d ##class(appcom.OEDispensing).Return(rowid)
		}

		;产生退药单
		d ##class(web.DHCSTRETREQUEST).CreateDrugReqByXtime(rowid,UserRowId)
		*/
	}
	if err s err="-301"
	Quit err
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  在医嘱执行时更新所有执行记录都的医嘱状态
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).VerifyAll("531546||1",590) 
ClassMethod VerifyAll(OrdItmRowId As %String, UserRowId As %String) As %String
{
	s err=0
		
	s StatusRowId=$O(^OEC("OSTAT",0,"Code","V",0))
	s Sub=0  f {
		s Sub=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub))
		Q:Sub=""
		s rowid=OrdItmRowId_"||"_Sub
		&SQL(Update SQLUser.OE_OrdExecExt Set OEORE_OrderStatus_DR=:StatusRowId Where OEORE_RowId=:rowid)
		do ##class(User.OEOrdExecOrdStatus).Save(rowid_"^"_StatusRowId_"^"_UserRowId_"^^^^")
		
		if SQLCODE s err=SQLCODE Quit
	}
	if err s err="-315"
	Quit err
}

/// Creator:      周志强
/// CreatDate:    2012.03.06
/// Description:  在医嘱执行时更新所有执行记录都的医嘱状态
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OrdItmRowId:医嘱Rowid,UserRowId:用户指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).ExecuteAll("531546||1",590) 
ClassMethod ExecuteAll(OrdItmRowId As %String, UserRowId As %String) As %String
{
	s err=0
		
	s StatusRowId=$O(^OEC("OSTAT",0,"Code","E",0))
	s Sub=0  f {
		s Sub=$O(^OEORD(+OrdItmRowId,"I",$P(OrdItmRowId,"||",2),"X",Sub))
		Q:Sub=""
		
		s rowid=OrdItmRowId_"||"_Sub
		&SQL(Update SQLUser.OE_OrdExecExt Set OEORE_OrderStatus_DR=:StatusRowId Where OEORE_RowId=:rowid)
		do ##class(User.OEOrdExecOrdStatus).Save(rowid_"^"_StatusRowId_"^"_UserRowId_"^^^^")
		if SQLCODE s err=SQLCODE Quit
	}
	if err s err="-315"
	Quit err
}

/// Creator:      周志强
/// CreatDate:    2012.03.15
/// Description:  不考虑执行状态给执行记录置免费标志,并进行计费冲负处理
/// Table:        OE_OrdItem,OE_OrdExec
/// Input:        OEORERowId:执行记录指针,UserRowId:用户指针,NewStatus: I/B,ChangeReasonRowId:原因指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).FreeCharge("77071||1||12",3,"I","1")
///  NewStatus:   I表示免费,	B表示取消免费
ClassMethod FreeCharge(OEORERowId As %String, UserRowId As %String, NewStatus As %String, ChangeReasonRowId As %String = "") As %String
{
	Q:(NewStatus'="B")&&(NewStatus'="I") 0
	
	s BillStatus=$P(^OEORD(+OEORERowId,"I",$P(OEORERowId,"||",2),"X",$P(OEORERowId,"||",3)),"^",6)
	i NewStatus=BillStatus Q "-310"
	q:(NewStatus="I")&&(BillStatus="R") -311
	q:(NewStatus="B")&&(BillStatus="TB") -313
	s Adm=$p(^OEORD(+OEORERowId),"^",1)
	s ChangeBillStatus=""
	i NewStatus="I" {
		if BillStatus="B" s ChangeBillStatus="I"
		if BillStatus="TB" s ChangeBillStatus="R"
	}
	i NewStatus="B" {
		if BillStatus="I" s ChangeBillStatus="TB"
		if BillStatus="R" s ChangeBillStatus="TB"
	}
	Ts
    s obj = ##class(User.OEOrdExec).%OpenId(OEORERowId)
    if $ISObject(obj) {
	    i (ChangeBillStatus'="") s obj.OEOREBilled=ChangeBillStatus	    
	    s sc=obj.%Save()
	    If $$$ISERR(sc) Tro  Quit "-306"
	    s obj1=##class(User.OEOrdExecExt).%OpenId(OEORERowId)
	    if $ISObject(obj1) {
		    s obj1.OEOREFreeChargeFlag=$s(NewStatus="I":"Y",1:"N")
		    s sc=obj1.%Save()
		    If $$$ISERR(sc) Tro  Quit "-309"
	    }
		d obj1.%Close()
		s obj1=""		
	    d obj.%Close()
	    s obj=""
	    ;插入状态变化表
	   	s objstatus=##class(User.OEOrdExecFreeCharge).%New(OEORERowId)
		d objstatus.FCCHParRefSetObjectId(OEORERowId)
		s objstatus.FCCHFreeChargeFlag=$s(NewStatus="I":"Y",1:"N")
		if ChangeReasonRowId'="" d objstatus.FCCHReasonDRSetObjectId(ChangeReasonRowId)
		s objstatus.FCCHDate=+$H
		s objstatus.FCCHTime=$P($H,",",2)
		d objstatus.FCCHUserDRSetObjectId(UserRowId)
		s sc=objstatus.%Save()
		If $$$ISERR(sc) Tro  Quit "-308"
	    d objstatus.%Close()
	    s objstatus=""
    }
    Tc
    s rtn=##Class(web.UDHCJFBILL).BILLN(Adm,UserRowId,"")	;马上帐单
    q 0
}

/// Creator:      周志强
/// CreatDate:    2012.04.13
/// Description:  将小时类医嘱的执行记录置上可计费标志
/// Table:        OE_OrdExec
/// Input:        OEORERowId:执行记录指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).SetBillFlag("77078||44||1","Y")
ClassMethod SetBillFlag(OEORERowId As %String, ExpectEndTime As %Time) As %String
{
	s exeobj=##class(User.OEOrdExec).%OpenId(OEORERowId)
	if $ISObject(exeobj) {
		s exeobj.OEOREExEnDate=exeobj.OEOREExStDate
		s exeobj.OEOREExEnTime=ExpectEndTime
		d exeobj.%Save()
		d exeobj.%Close()
		s exeobj=""
		s exeextobj=##class(User.OEOrdExecExt).%OpenId(OEORERowId)
		if $ISObject(exeextobj) {
			s exeextobj.OEOREBlillFlag="Y"
			d exeextobj.%Save()
			d exeextobj.%Close()
			s exeextobj=""
			Q 0
		}
	}

	Q 100
}

/// Creator:      周志强
/// CreatDate:    2012.04.13
/// Description:  重新设置小时类医嘱的停止时间,重新计费
/// Table:        OE_OrdExec
/// Input:        OEORERowId:执行记录指针
/// Return: 
/// OutPut:		  Err:程序执行返回值代码,标识成功与否
/// Others:       w ##class(appcom.OEOrdExec).ResetBillFlag(OEORERowId ,ExpectEndTime)
ClassMethod ResetBillFlag(OEORERowId As %String, ExpectEndTime As %Time, UserRowId As %String) As %String
{
    i ExpectEndTime=0 s ExpectEndTime=1
	s exeobj=##class(User.OEOrdExec).%OpenId(OEORERowId)
	if $ISObject(exeobj) {
		s exeobj.OEOREExEnDate=exeobj.OEOREExStDate
		set maxTime = $zth("23:59:59"),minTime = $zth("00:00:01")
		set exeobj.OEOREExEnTime=$s((maxTime<ExpectEndTime):maxTime,(ExpectEndTime<minTime):minTime,1:ExpectEndTime)
		if exeobj.OEOREBilled="B" {
			s exeobj.OEOREBilled="I"
		}elseif (exeobj.OEOREBilled="R") {
			s exeobj.OEOREBilled="I"
		}
			
		d exeobj.%Save()
		d exeobj.%Close()
		s exeobj=""
		s exeextobj=##class(User.OEOrdExecExt).%OpenId(OEORERowId)
		if $ISObject(exeextobj) {
			s exeextobj.OEOREBlillFlag="Y"
			d exeextobj.%Save()
			d exeextobj.%Close()
			s exeextobj=""

			s EpisodeID=$p(^OEORD(+OEORERowId),"^",1)
			if EpisodeID'="" {
				d ##Class(web.UDHCJFBILL).BILLN(EpisodeID,UserRowId,"")
				s MotherAdm=$p($g(^PAADM(EpisodeID)),"^",75)
				if MotherAdm'="" d ##Class(web.UDHCJFBILL).BILLN(MotherAdm,UserRowId,"")
			}

			Q 0
		}
	}

	Q 100
}

/// 执行记录添加备注 
/// add：2017-5-24 LX
/// w ##class(appcom.OEOrdExec).UpdateExecNotes("4||80||1","测试")
ClassMethod UpdateExecNotes(OEORERowId As %String, Notes As %String) As %String
{
	q:OEORERowId="" "-15500"
	Ts
	s obj=##class(User.OEOrdExec).%OpenId(OEORERowId)
	if $ISObject(obj) {
	 	s obj.OEORENotes=Notes
	    s sc=obj.%Save()
	    If $$$ISERR(sc) Tro  Quit "-15500"
	    d obj.%Close()
	}
    Tc
    q 0
}

/// 打开编辑执行记录备注界面 获取执行记录备注信息
ClassMethod GetOEORIExecNotes(OEORERowId As %String) As %String
{
	s Notes=""
	s obj=##class(User.OEOrdExec).%OpenId(OEORERowId)
	if $ISObject(obj) {
	 	s Notes=obj.OEORENotes
	    d obj.%Close()
	}
	q Notes
}

}
