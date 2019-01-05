/*----------------------------------------------------------------------------
   Normally, this in part of my geostool.lib utility library - I took it out
   to make the program compile without having to prepare a new version.
 ----------------------------------------------------------------------------*/
unsigned char _GeosXlate[]="����������� ����"
                           "����������� ����"
                           " �����      � "
                           "�������  �����"
                           "������ ��       "
                           "      ��       "
                           "                "
                           "                ",

              _GeosXlapp[]="�����������a����"
                           "�����������o����"
                           "+�����RC~'\"ؒ0"
                           "��������������"
                           "��������_ AAO��"
                           "-�\"\"`'��Y/�<>yY"
                           "+�,\"pAEAEEIIIIOO"
                           " OUUU,^~-`��,\",'";

unsigned char *GeosToIBM(unsigned char *s,int approx)
{
        unsigned char *p;

        for(p=s;*p;p++)                 // Ganzen String durchgehen
          if(*p>127)                    // Sonderzeichen?
            *p=(approx?_GeosXlapp:_GeosXlate)[*p-128];
                                        // Dann konvertieren
        return s;
}